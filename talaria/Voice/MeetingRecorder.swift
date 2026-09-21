import AVFoundation
import Observation
import Speech
import os

/// Records a meeting to an audio file while transcribing it on this phone in timestamped
/// segments. Recognition is restarted at pauses so long meetings stay light on memory.
@Observable @MainActor
final class MeetingRecorder {
    struct Segment: Identifiable {
        let id = UUID()
        let start: TimeInterval
        var text: String
    }

    private(set) var isRecording = false
    private(set) var segments: [Segment] = []
    /// Text of the segment still being recognised.
    private(set) var partial = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var fileURL: URL?
    var error: String?

    private let engine = AVAudioEngine()
    private var file: OSAllocatedUnfairLock<AVAudioFile?>?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let request = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private var generation = 0
    private var segmentStart: TimeInterval = 0
    private var startDate: Date?
    private var lastPartialChange = Date()
    private var ticker: Task<Void, Never>?

    /// Roll to a new recognition segment at the first pause after `rollAfter`, or at `rollMax` regardless.
    private let rollAfter: TimeInterval = 40
    private let rollMax: TimeInterval = 55

    func start() async {
        guard !isRecording else { return }
        error = nil
        guard await SpeechRecognizer.requestPermissions() else {
            error = VoiceError.permissionDenied.localizedDescription
            return
        }
        do {
            guard let r = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), r.isAvailable else {
                throw VoiceError.recognizerUnavailable
            }
            recognizer = r
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let input = engine.inputNode
            try? input.setVoiceProcessingEnabled(false)
            let format = input.outputFormat(forBus: 0)
            let url = Self.recordingsDirectory().appendingPathComponent(Self.fileName())
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let audioFile = OSAllocatedUnfairLock<AVAudioFile?>(initialState: try AVAudioFile(forWriting: url, settings: settings))
            file = audioFile
            fileURL = url
            let box = request
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                audioFile.withLock { try? $0?.write(from: buffer) }
                box.withLock { $0?.append(buffer) }
            }
            engine.prepare()
            try engine.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        segments = []
        partial = ""
        elapsed = 0
        startDate = Date()
        isRecording = true
        beginSegment()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        ticker?.cancel()
        generation += 1
        task?.cancel()
        task = nil
        request.withLock { $0?.endAudio(); $0 = nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file?.withLock { $0 = nil } // closes the file
        file = nil
        commit(partial)
        partial = ""
        if let startDate { elapsed = Date().timeIntervalSince(startDate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One line per segment with its start time, ready to attach to a message.
    var transcriptText: String {
        segments.map { "[\(Self.stamp($0.start))] \($0.text)" }.joined(separator: "\n")
    }

    static func stamp(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Documents/Meetings, visible in the Files app.
    static func recordingsDirectory() -> URL {
        let dir = URL.documentsDirectory.appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Meeting \(f.string(from: Date())).m4a"
    }

    // MARK: Segments

    private func tick() {
        guard isRecording, let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
        let age = elapsed - segmentStart
        let quiet = Date().timeIntervalSince(lastPartialChange) > 1.2
        if age > rollMax || (age > rollAfter && quiet) {
            commit(partial)
            partial = ""
            beginSegment()
        }
    }

    private func commit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        segments.append(Segment(start: segmentStart, text: t))
    }

    private func beginSegment() {
        generation += 1
        let gen = generation
        task?.cancel()
        segmentStart = elapsed
        lastPartialChange = Date()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        req.addsPunctuation = true
        req.taskHint = .dictation
        request.withLock { $0?.endAudio(); $0 = req }
        task = recognizer?.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, gen == self.generation else { return }
                if let text, text != self.partial {
                    self.partial = text
                    self.lastPartialChange = Date()
                }
                if done {
                    self.commit(self.partial)
                    self.partial = ""
                    try? await Task.sleep(for: .milliseconds(200))
                    if self.isRecording, gen == self.generation { self.beginSegment() }
                }
            }
        }
    }
}
