import AVFoundation
import Foundation

/// Speaks reply chunks with the voice configured on the Hermes server (dashboard
/// `POST /api/audio/speak`, Pocket TTS on prometheus). Chunks are fetched one at a time in order
/// and the next fetch overlaps playback of the current one. Audio plays through the recognizer's
/// engine when one is attached, so the echo canceller has the right reference. If the server
/// cannot synthesize, the rest of the session uses the on-device voice so nothing is lost.
@MainActor
final class HermesSpeaker: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    /// True while a fetch is in flight and nothing is audible yet.
    var isPreparing: Bool { isSpeaking && !isPlaying && !fallback.isSpeaking }
    var onFinished: (() -> Void)?
    /// Resolved at call time so a settings change applies to the next sentence.
    var auth: () -> GatewayAuth? = { nil }
    var useServer = true
    /// Plays through the shared audio engine; nil falls back to a standalone player.
    weak var output: (any AudioOutput)?
    private(set) var lastError: String?

    private let fallback = Speaker()
    private var pending: [String] = []
    private var ready: [AVAudioPCMBuffer] = []
    private var isPlaying = false
    private var player: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?
    private var generation = 0
    private var serverDown = false

    override init() {
        super.init()
        fallback.onFinished = { [weak self] in self?.checkFinished() }
    }

    /// Forget a previous session's server failure.
    func resetSession() {
        serverDown = false
        lastError = nil
    }

    func speak(_ text: String) {
        isSpeaking = true
        guard useServer, !serverDown, auth() != nil else { fallback.speak(text); return }
        pending.append(text)
        pump()
    }

    func stop() {
        generation += 1
        fetchTask?.cancel()
        fetchTask = nil
        pending = []
        ready = []
        output?.stopPlayback()
        player?.stop()
        player = nil
        isPlaying = false
        fallback.stop()
        isSpeaking = false
    }

    // MARK: Fetch pipeline

    private func pump() {
        guard fetchTask == nil, !pending.isEmpty, let auth = auth() else { return }
        let text = pending.removeFirst()
        let gen = generation
        fetchTask = Task { [weak self] in
            var audio: GatewayAuth.Audio?
            var failure: String?
            do { audio = try await auth.speak(text) } catch { failure = error.localizedDescription }
            guard let self, gen == self.generation else { return }
            self.fetchTask = nil
            if let audio, let buffer = self.decode(audio) {
                self.ready.append(buffer)
                self.playNextIfIdle()
                self.pump()
            } else {
                // Server voice is unavailable: finish this reply on the phone, in order.
                self.serverDown = true
                self.lastError = failure ?? "could not decode the server's audio"
                let rest = [text] + self.pending
                self.pending = []
                for t in rest { self.fallback.speak(t) }
            }
        }
    }

    /// Decode WAV/MP3/OGG bytes into a PCM buffer in the engine's playback format.
    private func decode(_ audio: GatewayAuth.Audio) -> AVAudioPCMBuffer? {
        let ext: String
        switch audio.mime.split(separator: ";").first.map(String.init) ?? "" {
        case "audio/mpeg", "audio/mp3": ext = "mp3"
        case "audio/ogg": ext = "ogg"
        case "audio/flac": ext = "flac"
        default: ext = "wav"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? audio.data.write(to: url)) != nil, let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: raw)) != nil else { return nil }
        guard let target = output?.playbackFormat else { return raw }
        if raw.format == target { return raw }
        guard let converter = AVAudioConverter(from: raw.format, to: target) else { return nil }
        let ratio = target.sampleRate / raw.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(raw.frameLength) * ratio) + 1024) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return raw
        }
        return error == nil ? out : nil
    }

    // MARK: Playback

    private func playNextIfIdle() {
        guard !isPlaying, !ready.isEmpty else { return }
        let buffer = ready.removeFirst()
        let gen = generation
        isPlaying = true
        if let output {
            output.play(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, gen == self.generation else { return }
                    self.playerEnded()
                }
            }
        } else if let p = try? AVAudioPlayer(data: Self.wavData(from: buffer)) {
            p.delegate = self
            player = p
            p.play()
        } else {
            playerEnded()
        }
    }

    /// Standalone-player fallback needs a container again; write a 16-bit WAV header.
    private static func wavData(from buffer: AVAudioPCMBuffer) -> Data {
        let rate = Int(buffer.format.sampleRate), ch = Int(buffer.format.channelCount), n = Int(buffer.frameLength)
        var pcm = Data(capacity: n * ch * 2)
        if let f = buffer.floatChannelData {
            for i in 0..<n { for c in 0..<ch {
                let v = Int16(max(-1, min(1, f[c][i])) * 32767)
                pcm.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) })
            } }
        }
        var d = Data()
        func u32(_ v: UInt32) { d.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        func u16(_ v: UInt16) { d.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(ch)); u32(UInt32(rate)); u32(UInt32(rate * ch * 2)); u16(UInt16(ch * 2)); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playerEnded() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.playerEnded() }
    }

    private func playerEnded() {
        player = nil
        isPlaying = false
        if !ready.isEmpty { playNextIfIdle() } else { checkFinished() }
    }

    private func checkFinished() {
        guard isSpeaking, !isPlaying, ready.isEmpty, pending.isEmpty, fetchTask == nil, !fallback.isSpeaking else { return }
        isSpeaking = false
        onFinished?()
    }
}
