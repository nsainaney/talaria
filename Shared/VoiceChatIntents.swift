import AppIntents
import Foundation
import os

/// What the voice chat intents drive. The app registers its voice controller here. The intents
/// conform to `LiveActivityIntent`, so the system performs them in the app's process, which is
/// alive during a voice chat because of the audio background mode.
@MainActor protocol VoiceChatCommands: AnyObject {
    var isVoiceChatActive: Bool { get }
    func pause()
    func resume()
    func stop()
    /// Cut off the reply being spoken; the chat goes on.
    func shush()
}

@MainActor enum VoiceChatIntentHost {
    static weak var commands: (any VoiceChatCommands)?
    static let log = Logger(subsystem: "com.sainaney.talaria", category: "intents")

    static func run(_ name: String, _ body: @MainActor (any VoiceChatCommands) -> Void) {
        guard let commands, commands.isVoiceChatActive else {
            log.info("voice \(name, privacy: .public): no voice chat running in \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
            return
        }
        log.info("voice \(name, privacy: .public) performed in \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
        body(commands)
    }
}

nonisolated struct PauseVoiceChatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause voice chat"
    static let description = IntentDescription("The microphone is ignored and nothing is sent; Hermes waits.")

    func perform() async throws -> some IntentResult {
        await VoiceChatIntentHost.run("pause") { $0.pause() }
        return .result()
    }
}

nonisolated struct ResumeVoiceChatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume voice chat"

    func perform() async throws -> some IntentResult {
        await VoiceChatIntentHost.run("resume") { $0.resume() }
        return .result()
    }
}

nonisolated struct ShushVoiceChatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Quiet"
    static let description = IntentDescription("Cuts off what Hermes is saying right now; the chat goes on.")

    func perform() async throws -> some IntentResult {
        await VoiceChatIntentHost.run("shush") { $0.shush() }
        return .result()
    }
}

nonisolated struct EndVoiceChatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End voice chat"
    static let description = IntentDescription("Stops listening and speaking. The chat stays in the inbox.")

    func perform() async throws -> some IntentResult {
        await VoiceChatIntentHost.run("end") { $0.stop() }
        return .result()
    }
}
