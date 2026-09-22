import AVFoundation
import Foundation

/// Speaks reply chunks with the voice configured on the Hermes server (dashboard
/// `POST /api/audio/speak`, Pocket TTS on prometheus). Chunks are fetched one at a time in order
/// and the next fetch overlaps playback of the current one. If the server cannot synthesize, the
/// rest of the session uses the on-device voice so nothing is lost.
@MainActor
final class HermesSpeaker: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    var onFinished: (() -> Void)?
    /// Resolved at call time so a settings change applies to the next sentence.
    var auth: () -> GatewayAuth? = { nil }
    var useServer = true
    private(set) var lastError: String?

    private let fallback = Speaker()
    private var pending: [String] = []
    private var ready: [Data] = []
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
        player?.stop()
        player = nil
        fallback.stop()
        isSpeaking = false
    }

    // MARK: Fetch pipeline

    private func pump() {
        guard fetchTask == nil, !pending.isEmpty, let auth = auth() else { return }
        let text = pending.removeFirst()
        let gen = generation
        fetchTask = Task { [weak self] in
            var audio: Data?
            var failure: String?
            do { audio = try await auth.speak(text) } catch { failure = error.localizedDescription }
            guard let self, gen == self.generation else { return }
            self.fetchTask = nil
            if let audio {
                self.ready.append(audio)
                self.playNextIfIdle()
                self.pump()
            } else {
                // Server voice is unavailable: finish this reply on the phone, in order.
                self.serverDown = true
                self.lastError = failure
                let rest = [text] + self.pending
                self.pending = []
                for t in rest { self.fallback.speak(t) }
            }
        }
    }

    private func playNextIfIdle() {
        guard player == nil, !ready.isEmpty else { return }
        let data = ready.removeFirst()
        guard let p = try? AVAudioPlayer(data: data) else { playNextIfIdle(); return }
        p.delegate = self
        player = p
        p.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playerEnded() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.playerEnded() }
    }

    private func playerEnded() {
        player = nil
        if !ready.isEmpty { playNextIfIdle() } else { checkFinished() }
    }

    private func checkFinished() {
        guard isSpeaking, player == nil, ready.isEmpty, pending.isEmpty, fetchTask == nil, !fallback.isSpeaking else { return }
        isSpeaking = false
        onFinished?()
    }
}
