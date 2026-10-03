import Foundation
import os

/// Timing marks for the voice loop, one `.notice` line each in the `bench` log category, so a
/// device log archive can be turned into a per-turn table by `scripts/voice-bench.py`. The marks,
/// in the order of one turn: `partial` (words still arriving), `utterance_end`, `submit`,
/// `message_start`, `tool_start` / `tool_end`, `first_delta`, `first_sentence`, `first_audio`,
/// `message_complete`, `reply_end`.
enum Bench {
    private static let log = Logger(subsystem: "com.sainaney.talaria", category: "bench")

    static func mark(_ name: StaticString, _ detail: String = "") {
        log.notice("\(name, privacy: .public) \(detail, privacy: .public)")
    }
}
