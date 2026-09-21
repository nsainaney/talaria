import AVFoundation
import Speech
import os

enum VoiceError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone or speech recognition permission was not granted."
        case .recognizerUnavailable: return "Speech recognition is not available for this language right now."
        }
    }
}

/// Streams microphone audio into on-device speech recognition and reports the text of the
/// current utterance as it forms. The audio engine runs with voice processing so the phone's own
/// speech output is echo-cancelled instead of transcribed.
@MainActor
final class SpeechRecognizer {
    /// Latest transcript of the utterance in progress (partial or final).
    var onText: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let request = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private var generation = 0

    static func requestPermissions() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        return status == .authorized
    }

    func start() throws {
        guard !isRunning else { return }
        guard let r = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), r.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        recognizer = r
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        let box = request
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            box.withLock { $0?.append(buffer) }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        beginUtterance()
    }

    /// Close the current utterance and start listening for the next one.
    func nextUtterance() {
        guard isRunning else { return }
        beginUtterance()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        task?.cancel()
        task = nil
        request.withLock { $0?.endAudio(); $0 = nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginUtterance() {
        generation += 1
        let gen = generation
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        req.addsPunctuation = true
        req.taskHint = .dictation
        request.withLock { $0?.endAudio(); $0 = req }
        task = recognizer?.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { $0 as NSError }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, gen == self.generation else { return }
                if let text { self.onText?(text) }
                if isFinal {
                    self.beginUtterance()
                } else if let failure {
                    // 1110 is "no speech detected" after a long silence; anything else is worth showing.
                    if !(failure.domain == "kAFAssistantErrorDomain" && failure.code == 1110) { self.onError?(failure) }
                    try? await Task.sleep(for: .milliseconds(300))
                    if self.isRunning, gen == self.generation { self.beginUtterance() }
                }
            }
        }
    }
}
