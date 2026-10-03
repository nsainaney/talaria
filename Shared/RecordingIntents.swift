import AppIntents
import Foundation
import os

/// What the recording intents drive. The app registers its recorder here. The intents conform to
/// `LiveActivityIntent`, which makes the system perform them in the app's process (launching it in
/// the background if needed) rather than in the widget extension, where nothing is registered.
/// `AudioRecordingIntent` marks them as recording intents; it requires a Live Activity while recording.
@MainActor protocol RecordingCommands: AnyObject {
    var isRecordingActive: Bool { get }
    func start() async throws
    func pause() throws
    func resume() async throws
    func stop() async throws
    /// Discard the recording: nothing is kept or sent.
    func cancel() async throws
}

/// Thrown by the recorder when iOS refuses to start the microphone in the background; the intent
/// then brings the app forward and starts there.
nonisolated enum RecordingStartError: Error {
    case needsForeground(String)
}

@MainActor enum RecordingIntentHost {
    static weak var commands: (any RecordingCommands)?
    static let log = Logger(subsystem: "com.sainaney.talaria", category: "intents")

    /// Start in the background; if iOS refuses the microphone there, open the app and start again.
    static func startOrContinueInForeground(_ intent: some AppIntent) async throws {
        do {
            try await run("start") { try await $0.start() }
        } catch RecordingStartError.needsForeground(let why) {
            log.info("background start refused (\(why, privacy: .public)); continuing in the foreground")
            try await intent.continueInForeground("Talaria opens to start recording.", alwaysConfirm: false)
            try await run("start (foreground)") { try await $0.start() }
        }
    }

    /// Run one command, logging which process performed it and why it failed, if it did.
    static func run(_ name: String, _ body: @MainActor (any RecordingCommands) async throws -> Void) async throws {
        guard let commands else {
            log.error("\(name, privacy: .public) performed in \(Bundle.main.bundleIdentifier ?? "?", privacy: .public) with no recorder registered")
            return
        }
        log.info("\(name, privacy: .public) performed in \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
        do { try await body(commands) } catch {
            log.error("\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

nonisolated struct StartRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start recording"
    static let description = IntentDescription("Records audio; when stopped, the recording is sent to Speakr for transcription.")
    /// Background first; the app is opened only if iOS refuses to start the microphone there.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.startOrContinueInForeground(self)
        return .result()
    }
}

nonisolated struct PauseRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Pause recording"

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("pause") { try $0.pause() }
        return .result()
    }
}

nonisolated struct ResumeRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Resume recording"

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("resume") { try await $0.resume() }
        return .result()
    }
}

nonisolated struct StopRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let description = IntentDescription("Stops the recording and sends it to Speakr.")

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("stop") { try await $0.stop() }
        return .result()
    }
}

nonisolated struct CancelRecordingIntent: LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Cancel recording"
    static let description = IntentDescription("Stops the recording without sending it; the audio is kept on the phone.")

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("cancel") { try await $0.cancel() }
        return .result()
    }
}

/// Control Center toggle: on starts, off stops. Performed in the app process in the background.
nonisolated struct ToggleRecordingIntent: SetValueIntent, LiveActivityIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Recording")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if value {
            try await RecordingIntentHost.startOrContinueInForeground(self)
        } else {
            try await RecordingIntentHost.run("stop") { try await $0.stop() }
        }
        return .result()
    }
}
