import AppIntents

/// What the recording intents drive. The app registers its recorder here; inside the widget
/// extension nothing is registered, and these intents are never performed there anyway:
/// audio recording intents run in the app's process, launching it in the background if needed.
@MainActor protocol RecordingCommands: AnyObject {
    func start() async throws
    func pause() throws
    func resume() async throws
    func stop() async throws
}

@MainActor enum RecordingIntentHost {
    static weak var commands: (any RecordingCommands)?
}

nonisolated struct StartRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start recording"
    static let description = IntentDescription("Records audio; when stopped, the recording is sent to Speakr for transcription.")

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.commands?.start()
        return .result()
    }
}

nonisolated struct PauseRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Pause recording"

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.commands?.pause()
        return .result()
    }
}

nonisolated struct ResumeRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Resume recording"

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.commands?.resume()
        return .result()
    }
}

nonisolated struct StopRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let description = IntentDescription("Stops the recording and sends it to Speakr.")

    func perform() async throws -> some IntentResult {
        try await RecordingIntentHost.commands?.stop()
        return .result()
    }
}

/// Control Center toggle: on starts, off stops.
nonisolated struct ToggleRecordingIntent: SetValueIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record"

    @Parameter(title: "Recording")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if value {
            try await RecordingIntentHost.commands?.start()
        } else {
            try await RecordingIntentHost.commands?.stop()
        }
        return .result()
    }
}
