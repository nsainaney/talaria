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
}

@MainActor enum RecordingIntentHost {
    static weak var commands: (any RecordingCommands)?
    static let log = Logger(subsystem: "com.sainaney.talaria", category: "intents")

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

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("start") { try await $0.start() }
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

/// Control Center button. iOS does not let an app begin recording while it is in the background,
/// so this opens the app and starts there; a running recording is stopped instead.
nonisolated struct RecordControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Record"
    static let description = IntentDescription("Opens Talaria and starts a recording, or stops the one running.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.run("control") { commands in
            if commands.isRecordingActive { try await commands.stop() } else { try await commands.start() }
        }
        return .result()
    }
}
