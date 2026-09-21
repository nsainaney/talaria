import AVFoundation

/// Speaks reply text through the system synthesizer, queueing one utterance per sentence chunk
/// so speech starts while the reply is still streaming.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    var onFinished: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queued = 0

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    /// Best installed voice for the current language: premium, then enhanced, then default.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: lang)
    }()

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.prefersAssistiveTechnologySettings = false
        queued += 1
        isSpeaking = true
        synth.speak(u)
    }

    func stop() {
        queued = 0
        isSpeaking = false
        synth.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    private func utteranceEnded() {
        queued = max(0, queued - 1)
        if queued == 0, isSpeaking {
            isSpeaking = false
            onFinished?()
        }
    }
}
