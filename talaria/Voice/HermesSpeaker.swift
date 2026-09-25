import AVFoundation
import Foundation
import os

/// Speaks reply text with the voice configured on the Hermes server. Preferred path: the
/// dashboard's `/api/audio/speak-stream` WebSocket — sentences go up as they arrive and PCM comes
/// back while the server is still synthesising, so speech starts a fraction of a second after the
/// first sentence. Falls back to `POST /api/audio/speak` (one WAV per sentence, fetched in order
/// with the next fetch overlapping playback) when the server has no streaming provider or the
/// socket fails, and to the on-device voice when the server cannot synthesize at all. Audio plays
/// through the recognizer's engine when one is attached, so the echo canceller has the right
/// reference.
@MainActor
final class HermesSpeaker: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    /// True while fetching or synthesising and nothing is audible yet.
    var isPreparing: Bool { isSpeaking && !isPlaying && !fallback.isSpeaking }
    var onFinished: (() -> Void)?
    /// Resolved at call time so a settings change applies to the next sentence.
    var auth: () -> GatewayAuth? = { nil }
    var useServer = true
    /// Plays through the shared audio engine; nil falls back to a standalone player (whole-file only).
    weak var output: (any AudioOutput)?
    private(set) var lastError: String?

    private static let log = Logger(subsystem: "com.sainaney.talaria", category: "voice")
    private let fallback = Speaker()
    private var generation = 0
    private var serverDown = false

    // Streaming path
    private var stream: SpeakStream?
    private var streamFormat: (rate: Double, channels: Int) = (24000, 1)
    private var streamRemainder = Data()
    /// Buffers scheduled on the engine and not yet played back.
    private var queued = 0
    private var streamFailures = 0
    private var streamUnavailable = false
    private var idleFinishTask: Task<Void, Never>?

    // Whole-file path
    private var pending: [String] = []
    private var ready: [AVAudioPCMBuffer] = []
    private var playerBusy = false
    private var player: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?

    private var isPlaying: Bool { playerBusy || queued > 0 }
    private var streamIdle: Bool { stream?.ended ?? true }

    override init() {
        super.init()
        fallback.onFinished = { [weak self] in self?.checkFinished() }
    }

    /// Forget a previous session's server failure.
    func resetSession() {
        serverDown = false
        streamUnavailable = false
        streamFailures = 0
        lastError = nil
    }

    func speak(_ text: String) {
        isSpeaking = true
        guard useServer, !serverDown, let auth = auth() else { fallback.speak(text); return }
        if !streamUnavailable, output != nil {
            streamSpeak(text, auth: auth)
        } else {
            pending.append(text)
            pump()
        }
    }

    /// The current reply has no more sentences. Streaming needs this to know when to ask the
    /// server for `end`; the whole-file path finishes on its own.
    func finish() {
        idleFinishTask?.cancel()
        stream?.finish()
    }

    func stop() {
        generation += 1
        idleFinishTask?.cancel()
        stream?.stop()
        stream = nil
        streamRemainder = Data()
        queued = 0
        fetchTask?.cancel()
        fetchTask = nil
        pending = []
        ready = []
        output?.stopPlayback()
        player?.stop()
        player = nil
        playerBusy = false
        fallback.stop()
        isSpeaking = false
    }

    // MARK: Streaming

    private func streamSpeak(_ text: String, auth: GatewayAuth) {
        if stream == nil || stream!.finished || stream!.ended {
            let s = SpeakStream(auth: auth)
            let gen = generation
            s.onEvent = { [weak self] event in
                guard let self, gen == self.generation, self.stream === s else { return }
                self.handle(event, from: s)
            }
            stream = s
            streamRemainder = Data()
        }
        stream?.send(text)
        // A reply whose end never gets signalled (chat error mid-turn) must not leave the
        // socket open and the state stuck on speaking: ask for the end after a quiet spell.
        idleFinishTask?.cancel()
        idleFinishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.stream?.finish()
        }
    }

    private func handle(_ event: SpeakStream.Event, from s: SpeakStream) {
        switch event {
        case .start(let rate, let channels):
            streamFormat = (rate, channels)
        case .audio(let data):
            streamFailures = 0
            var bytes = streamRemainder + data
            let frameBytes = 2 * streamFormat.channels
            let whole = bytes.count - bytes.count % frameBytes
            streamRemainder = Data(bytes.suffix(from: whole))
            bytes = Data(bytes.prefix(whole))
            guard let raw = Self.pcmBuffer(bytes, rate: streamFormat.rate, channels: streamFormat.channels),
                  let buffer = convert(raw) else { return }
            schedule(buffer)
        case .end:
            checkFinished()
        case .fallback:
            Self.log.info("speak-stream: server has no streaming TTS; using whole-file speech")
            streamUnavailable = true
            respeakElsewhere(s)
        case .closed(let error):
            if s.gotAudio {
                // Dropped mid-reply after audio: what played, played. Two in a row and the
                // session goes whole-file.
                streamFailures += 1
                if streamFailures >= 2 { streamUnavailable = true }
                Self.log.error("speak-stream dropped: \(error.localizedDescription, privacy: .public)")
                checkFinished()
            } else {
                Self.log.error("speak-stream failed: \(error.localizedDescription, privacy: .public)")
                streamUnavailable = true
                respeakElsewhere(s)
            }
        }
    }

    /// The stream produced nothing: say its sentences through the whole-file path instead.
    private func respeakElsewhere(_ s: SpeakStream) {
        if stream === s { stream = nil }
        pending.append(contentsOf: s.sent)
        pump()
        checkFinished()
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        guard let output else { return }
        let gen = generation
        queued += 1
        output.play(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                self.queued = max(0, self.queued - 1)
                self.checkFinished()
            }
        }
    }

    /// Little-endian 16-bit PCM → float buffer at the stream's own rate.
    private static func pcmBuffer(_ data: Data, rate: Double, channels: Int) -> AVAudioPCMBuffer? {
        let frames = data.count / (2 * channels)
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for c in 0..<channels {
                for i in 0..<frames { out[c][i] = Float(Int16(littleEndian: src[i * channels + c])) / 32768 }
            }
        }
        return buffer
    }

    // MARK: Whole-file fetch pipeline

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
        return convert(raw)
    }

    /// Into the engine's playback format (no-op without an engine or when it already matches).
    private func convert(_ raw: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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

    // MARK: Whole-file playback

    private func playNextIfIdle() {
        guard !playerBusy, !ready.isEmpty else { return }
        let buffer = ready.removeFirst()
        let gen = generation
        playerBusy = true
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
        playerBusy = false
        if !ready.isEmpty { playNextIfIdle() } else { checkFinished() }
    }

    private func checkFinished() {
        guard isSpeaking, !isPlaying, streamIdle, ready.isEmpty, pending.isEmpty, fetchTask == nil,
              !fallback.isSpeaking else { return }
        idleFinishTask?.cancel()
        stream = nil
        isSpeaking = false
        onFinished?()
    }
}
