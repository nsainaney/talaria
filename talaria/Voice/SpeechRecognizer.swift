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

/// Something that can play decoded audio while the microphone stays open.
@MainActor
protocol AudioOutput: AnyObject {
    var playbackFormat: AVAudioFormat { get }
    func play(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void)
    func stopPlayback()
}

private let log = Logger(subsystem: "com.sainaney.talaria", category: "voice")

/// Streams microphone audio into on-device speech recognition and reports the text of the
/// current utterance as it forms. The audio engine runs with voice processing so the phone's own
/// speech output is echo-cancelled instead of transcribed; reply audio plays through the same
/// engine so the canceller has the right reference.
@MainActor
final class SpeechRecognizer: AudioOutput {
    /// Latest transcript of the utterance in progress (partial or final).
    var onText: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    /// Microphone level 0…1, about ten times a second, for a meter.
    var onLevel: ((Float) -> Void)?
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let request = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private let level = OSAllocatedUnfairLock<(peak: Float, buffers: Int)>(initialState: (0, 0))
    private var generation = 0
    private var meterTask: Task<Void, Never>?

    init() {
        engine.attach(playerNode)
    }

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
        do { try input.setVoiceProcessingEnabled(true) } catch { log.error("voice processing unavailable: \(error.localizedDescription)") }
        // Output graph first, then prepare, then read the input format the I/O unit settled on.
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        let format = input.outputFormat(forBus: 0)
        log.info("engine input format \(format.sampleRate) Hz, \(format.channelCount) ch; voice processing \(input.isVoiceProcessingEnabled); on-device STT \(r.supportsOnDeviceRecognition)")
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.recognizerUnavailable }
        let box = request
        let meter = level
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            box.withLock { $0?.append(buffer) }
            var peak: Float = 0
            if let ch = buffer.floatChannelData?[0] {
                for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) { peak = max(peak, abs(ch[i])) }
            }
            meter.withLock { $0 = (max($0.peak, peak), $0.buffers + 1) }
        }
        try engine.start()
        isRunning = true
        beginUtterance()
        meterTask = Task { [weak self] in
            var reported = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let (peak, buffers) = self.level.withLock { let v = $0; $0.peak = 0; return v }
                if buffers > reported, reported == 0 { log.info("first mic buffer received") }
                reported = buffers
                self.onLevel?(min(1, peak * 4))
            }
        }
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
        meterTask?.cancel()
        task?.cancel()
        task = nil
        request.withLock { $0?.endAudio(); $0 = nil }
        playerNode.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level.withLock { $0 = (0, 0) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: AudioOutput

    func play(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) {
        guard isRunning else { completion(); return }
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stopPlayback() {
        playerNode.stop()
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
                    log.error("recognizer error \(failure.domain) \(failure.code): \(failure.localizedDescription)")
                    // 1110 is "no speech detected" after a long silence; anything else is worth showing.
                    if !(failure.domain == "kAFAssistantErrorDomain" && failure.code == 1110) { self.onError?(failure) }
                    try? await Task.sleep(for: .milliseconds(300))
                    if self.isRunning, gen == self.generation { self.beginUtterance() }
                }
            }
        }
    }
}
