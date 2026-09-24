import ActivityKit
import AVFoundation
import Foundation
import Observation
import UIKit
import os

/// Records audio to a file, driven from the widget, the Live Activity, Control Center or the app.
/// A phone call pauses the recording and it resumes by itself when the call ends. On stop, the
/// file goes to Speakr for transcription on a background transfer, so the app can be closed.
@Observable @MainActor
final class BackgroundRecorder: RecordingCommands {
    static let shared = BackgroundRecorder()

    private(set) var state: RecordingState

    /// Called before recording starts so the app can release the microphone (voice mode).
    @ObservationIgnored var willStart: (() -> Void)?

    @ObservationIgnored private let log = Logger(subsystem: "com.sainaney.talaria", category: "recorder")
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var userPaused = false
    /// Seconds recorded before the current run, and when the current run started.
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var runningSince: Date?
    @ObservationIgnored private var resumeAttempts: Task<Void, Never>?
    @ObservationIgnored private var activity: Activity<RecordingActivityAttributes>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    enum Error: LocalizedError {
        case microphoneDenied, alreadyRecording, notRecording, couldNotStart
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: return "Talaria needs microphone access. Open the app once to allow it."
            case .alreadyRecording: return "A recording is already running."
            case .notRecording: return "No recording is running."
            case .couldNotStart: return "The microphone could not be started."
            }
        }
    }

    private init() {
        state = RecordingState.load()
        RecordingIntentHost.commands = self
        observe()
    }

    /// Call once at launch: reconcile with what happened while the app was not running.
    func prepare() {
        _ = SpeakrUploader.shared // adopt background transfers that finished meanwhile
        activity = Activity<RecordingActivityAttributes>.activities.first
        var s = state
        s.micGranted = AVAudioApplication.shared.recordPermission == .granted
        s.speakrConfigured = speakr != nil
        if s.isActive, recorder == nil {
            // The process was killed mid-recording; what was written stays in Files.
            s.phase = .failed
            s.timerStart = nil
            s.interrupted = false
            s.message = "Recording stopped when the app was closed. The audio is in Files › Talaria › Meetings."
        }
        set(s)
        if state.phase != .uploading { endActivity(after: 0) }
    }

    private var elapsed: TimeInterval {
        accumulated + (runningSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private var speakr: SpeakrClient? { ServerSettings().speakr }

    private func set(_ s: RecordingState) {
        state = s
        s.save()
        updateActivity()
    }

    private func update(_ change: (inout RecordingState) -> Void) {
        var s = state
        change(&s)
        set(s)
    }

    // MARK: Commands

    func start() async throws {
        guard !state.isActive, recorder == nil else { throw Error.alreadyRecording }
        var granted = AVAudioApplication.shared.recordPermission == .granted
        if !granted, AVAudioApplication.shared.recordPermission == .undetermined {
            granted = await AVAudioApplication.requestRecordPermission()
        }
        update { $0.micGranted = granted }
        guard granted else { throw Error.microphoneDenied }
        willStart?()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let name = Self.fileName()
        let url = MeetingRecorder.recordingsDirectory().appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.prepareToRecord()
        // The Live Activity comes first: background recording from an intent expects one to be showing.
        startActivity()
        guard r.record() else {
            endActivity(after: 0)
            try? session.setActive(false)
            throw Error.couldNotStart
        }
        recorder = r
        fileURL = url
        userPaused = false
        accumulated = 0
        runningSince = Date()
        log.info("recording to \(name, privacy: .public)")
        set(RecordingState(phase: .recording, timerStart: Date(), recorded: 0, fileName: name,
                           micGranted: true, speakrConfigured: speakr != nil))
    }

    func pause() throws {
        guard let recorder, state.phase == .recording else { throw Error.notRecording }
        userPaused = true
        resumeAttempts?.cancel()
        recorder.pause()
        accumulated = elapsed
        runningSince = nil
        let done = accumulated
        update { $0.phase = .paused; $0.recorded = done; $0.timerStart = nil; $0.interrupted = false }
    }

    func resume() async throws {
        guard let recorder, state.phase == .paused else { throw Error.notRecording }
        userPaused = false
        try AVAudioSession.sharedInstance().setActive(true)
        guard recorder.record() else { throw Error.couldNotStart }
        runningSince = Date()
        let start = Date().addingTimeInterval(-accumulated)
        update { $0.phase = .recording; $0.timerStart = start; $0.interrupted = false }
    }

    func stop() async throws {
        guard let recorder, state.isActive else { throw Error.notRecording }
        resumeAttempts?.cancel()
        let total = elapsed
        recorder.stop()
        self.recorder = nil
        runningSince = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let fileURL else { return }
        self.fileURL = nil
        log.info("stopped after \(Int(total))s")

        guard let client = speakr else {
            finish(.failed, "Saved on this phone. Set the Speakr server in Settings to have recordings transcribed.", recorded: total)
            return
        }
        do {
            try SpeakrUploader.shared.enqueue(file: fileURL, client: client)
            update {
                $0.phase = .uploading; $0.recorded = total; $0.timerStart = nil; $0.interrupted = false
                $0.message = "Sending to Speakr…"
            }
        } catch {
            finish(.failed, "Could not start the upload: \(error.localizedDescription)", recorded: total)
        }
    }

    /// Clear the outcome shown after a stop.
    func clear() {
        guard !state.isActive, state.phase != .uploading else { return }
        set(RecordingState(micGranted: state.micGranted, speakrConfigured: speakr != nil))
    }

    /// Called by the uploader when Speakr answers, possibly after the app was relaunched for it.
    func uploadFinished(name: String, status: Int?, body: Data, error: (any Swift.Error)?) {
        if let error {
            finish(.failed, "Upload failed: \(error.localizedDescription). The audio is in Files › Talaria › Meetings.")
            return
        }
        guard let status, (200..<300).contains(status) else {
            let text = String(data: body.prefix(200), encoding: .utf8) ?? ""
            finish(.failed, "Speakr returned HTTP \(status ?? 0). \(text) The audio is in Files › Talaria › Meetings.")
            return
        }
        let id = SpeakrClient.recordingId(from: body)
        update {
            $0.phase = .sent
            $0.speakrRecordingId = id
            $0.message = id.map { "Sent to Speakr as recording #\($0). It is being transcribed." } ?? "Sent to Speakr for transcription."
        }
        endActivity(after: 8)
    }

    private func finish(_ phase: RecordingState.Phase, _ message: String, recorded: TimeInterval? = nil) {
        update {
            $0.phase = phase; $0.timerStart = nil; $0.interrupted = false; $0.message = message
            if let recorded { $0.recorded = recorded }
        }
        endActivity(after: 8)
    }

    // MARK: Interruptions (calls, FaceTime, other apps taking the mic)

    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            Task { @MainActor in BackgroundRecorder.shared.interruption(type) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BackgroundRecorder.shared.mediaServicesReset() }
        })
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let r = BackgroundRecorder.shared
                if r.state.interrupted, !r.userPaused { _ = r.tryResume() }
            }
        })
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            guard recorder != nil, state.phase == .recording, !state.interrupted else { return }
            log.info("interrupted; will resume when the call ends")
            recorder?.pause()
            accumulated = elapsed
            runningSince = nil
            let done = accumulated
            update { $0.interrupted = true; $0.recorded = done; $0.timerStart = nil }
            scheduleResumeAttempts()
        case .ended:
            guard state.interrupted, !userPaused else { return }
            if !tryResume() { scheduleResumeAttempts() }
        default:
            break
        }
    }

    /// Try to pick the recording back up; false if the session is still taken (call still on).
    @discardableResult
    private func tryResume() -> Bool {
        guard let recorder, state.interrupted, !userPaused else { return false }
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { return false }
        guard recorder.record() else { return false }
        resumeAttempts?.cancel()
        runningSince = Date()
        let start = Date().addingTimeInterval(-accumulated)
        log.info("resumed after interruption")
        update { $0.interrupted = false; $0.timerStart = start; $0.phase = .recording }
        return true
    }

    /// The end-of-interruption notice does not always arrive (calls are the usual case), so keep trying.
    private func scheduleResumeAttempts() {
        resumeAttempts?.cancel()
        resumeAttempts = Task { [weak self] in
            for _ in 0..<900 { // up to 30 minutes
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.state.interrupted else { return }
                if self.tryResume() { return }
            }
        }
    }

    private func mediaServicesReset() {
        guard state.isActive else { return }
        log.error("media services were reset; stopping")
        Task { try? await stop() }
    }

    // MARK: Live Activity

    private var content: RecordingActivityAttributes.ContentState {
        .init(phase: state.phase, timerStart: state.timerStart, recorded: state.recorded,
              interrupted: state.interrupted, message: state.message)
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for old in Activity<RecordingActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let first = RecordingActivityAttributes.ContentState(phase: .recording, timerStart: Date(), recorded: 0, interrupted: false, message: nil)
        do {
            activity = try Activity.request(attributes: RecordingActivityAttributes(startedAt: Date()),
                                            content: ActivityContent(state: first, staleDate: nil))
        } catch {
            log.error("live activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateActivity() {
        guard let activity else { return }
        let c = content
        Task { await activity.update(ActivityContent(state: c, staleDate: nil)) }
    }

    private func endActivity(after seconds: TimeInterval) {
        guard let activity else { return }
        self.activity = nil
        let c = content
        Task {
            await activity.end(ActivityContent(state: c, staleDate: nil),
                               dismissalPolicy: seconds > 0 ? .after(.now + seconds) : .immediate)
        }
    }

    private static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Recording \(f.string(from: Date())).m4a"
    }
}
