import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

/// What a voice chat with Hermes is doing, as the widget and the Live Activity show it.
/// Written by the app into the app group; read by the widget extension.
nonisolated struct VoiceChatState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case off, listening, thinking, speaking, paused }

    static let stateKey = "voicechat.state"

    var phase: Phase = .off
    var startedAt: Date?
    /// The chat's title, when it has one.
    var title: String?

    var isActive: Bool { phase != .off }

    static func load() -> VoiceChatState {
        guard let data = RecordingShared.defaults.data(forKey: stateKey),
              let s = try? JSONDecoder().decode(VoiceChatState.self, from: data) else { return VoiceChatState() }
        return s
    }

    @MainActor func save() {
        if let data = try? JSONEncoder().encode(self) {
            RecordingShared.defaults.set(data, forKey: Self.stateKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: RecordingShared.widgetKind)
    }
}

/// The Live Activity shown in the Dynamic Island and on the Lock Screen during a voice chat.
nonisolated struct VoiceChatActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: VoiceChatState.Phase
        var title: String?
    }

    var startedAt: Date
}

/// Icons, colors and words for a voice chat's phases, shared by the app, the widget and the Live Activity.
nonisolated enum VoiceChatStyle {
    static func icon(_ phase: VoiceChatState.Phase) -> String {
        switch phase {
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .paused: return "pause.circle.fill"
        case .off: return "waveform"
        }
    }

    static func color(_ phase: VoiceChatState.Phase) -> Color {
        switch phase {
        case .listening: return .red
        case .speaking: return .blue
        case .thinking, .paused, .off: return .secondary
        }
    }

    static func title(_ phase: VoiceChatState.Phase) -> String {
        switch phase {
        case .listening: return "Listening"
        case .thinking: return "Hermes is thinking"
        case .speaking: return "Hermes is speaking"
        case .paused: return "Paused"
        case .off: return "Voice chat"
        }
    }
}
