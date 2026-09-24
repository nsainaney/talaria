import ActivityKit
import Foundation

/// The Live Activity shown in the Dynamic Island and on the Lock Screen while recording.
nonisolated struct RecordingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: RecordingState.Phase
        var timerStart: Date?
        var recorded: TimeInterval
        var interrupted: Bool
        var message: String?
    }

    var startedAt: Date
}
