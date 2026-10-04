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
    /// The phone is talking: the microphone input is muted inside the voice-processing unit for
    /// the whole reply, so nothing of the phone's own voice can reach the recognizer. Off again
    /// the moment the last sample has played back.
    func setPhoneTalking(_ on: Bool)
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
    /// The system microphone mode (Standard, Voice Isolation, Wide Spectrum), at start and whenever
    /// the person changes it in Control Center. Voice Isolation is the system's own ML filter for
    /// background noise and other voices; an app cannot set it, only ask for the picker.
    var onMicrophoneMode: ((AVCaptureDevice.MicrophoneMode) -> Void)?
    /// While the input is muted, the voice-processing unit still watches for the person talking
    /// (its own echo-aware detector, the one behind "you're muted"). True when speech starts,
    /// false when it ends.
    private(set) var isRunning = false
    private(set) var isPhoneTalking = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let request = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private let level = OSAllocatedUnfairLock<(peak: Float, buffers: Int)>(initialState: (0, 0))
    /// The last half minute of microphone audio at 16 kHz mono, for the speaker verifier. Filled
    /// from the tap after the voice-processing unit, so it is the same audio the recognizer hears.
    private let recent = OSAllocatedUnfairLock(initialState: AudioRing(seconds: 30))
    private var generation = 0
    private var meterTask: Task<Void, Never>?

    static let verifierFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// The most recent `seconds` of microphone audio, 16 kHz mono, oldest first.
    func recentAudio(seconds: Double) -> [Float] {
        recent.withLock { $0.last(Int(seconds * 16000)) }
    }

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
        let ring = recent
        ring.withLock { $0.clear() }
        let converter = AVAudioConverter(from: format, to: Self.verifierFormat)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            box.withLock { $0?.append(buffer) }
            var peak: Float = 0
            if let ch = buffer.floatChannelData?[0] {
                for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) { peak = max(peak, abs(ch[i])) }
            }
            meter.withLock { $0 = (max($0.peak, peak), $0.buffers + 1) }
            if let converter, let mono = Self.resample(buffer, with: converter) { ring.withLock { $0.append(mono) } }
        }
        try engine.start()
        isRunning = true
        beginUtterance()
        log.info("microphone mode \(Self.describe(AVCaptureDevice.activeMicrophoneMode)); AGC \(input.isVoiceProcessingAGCEnabled)")
        onMicrophoneMode?(AVCaptureDevice.activeMicrophoneMode)
        meterTask = Task { [weak self] in
            var reported = 0
            var ticks = 0
            var micMode = AVCaptureDevice.activeMicrophoneMode
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let (peak, buffers) = self.level.withLock { let v = $0; $0.peak = 0; return v }
                if buffers > reported, reported == 0 { log.info("first mic buffer received") }
                reported = buffers
                self.onLevel?(min(1, peak * 4))
                // The mode is a class property without a notification; a once-a-second check is enough.
                ticks += 1
                if ticks % 10 == 0, AVCaptureDevice.activeMicrophoneMode != micMode {
                    micMode = AVCaptureDevice.activeMicrophoneMode
                    log.info("microphone mode now \(Self.describe(micMode))")
                    self.onMicrophoneMode?(micMode)
                }
            }
        }
    }

    /// One tap buffer, converted to 16 kHz mono float. The converter keeps its own state between
    /// calls, so consecutive buffers resample without seams.
    private nonisolated static func resample(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float]? {
        let ratio = verifierFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: verifierFormat, frameCapacity: capacity) else { return nil }
        var handed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if handed { status.pointee = .noDataNow; return nil }
            handed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let ch = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
    }

    /// Opens the Control Center microphone-mode picker, the only way an app can offer Voice
    /// Isolation. iOS remembers the choice for this app.
    static func showMicrophoneModePicker() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }

    static func describe(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .standard: "standard"
        case .voiceIsolation: "voice isolation"
        case .wideSpectrum: "wide spectrum"
        @unknown default: "unknown"
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
        if engine.inputNode.isVoiceProcessingEnabled { engine.inputNode.isVoiceProcessingInputMuted = false }
        isPhoneTalking = false
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

    func setPhoneTalking(_ on: Bool) {
        guard isRunning, isPhoneTalking != on else { return }
        isPhoneTalking = on
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled { input.isVoiceProcessingInputMuted = on }
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
