import SwiftUI

/// One set of icons and colors for the recorder, shared by the app, the widget and the Live Activity.
nonisolated enum RecorderStyle {
    struct Action: Sendable {
        let name: String
        let symbol: String
        let color: Color

        static let record = Action(name: "Record", symbol: "mic.fill", color: .red)
        static let pause = Action(name: "Pause", symbol: "pause.fill", color: .orange)
        static let resume = Action(name: "Resume", symbol: "record.fill", color: .red)
        static let cancel = Action(name: "Cancel", symbol: "xmark", color: .gray)
        static let complete = Action(name: "Complete", symbol: "checkmark", color: .green)
        static let close = Action(name: "Close", symbol: "xmark", color: .gray)
    }

    static func icon(_ phase: RecordingState.Phase, interrupted: Bool) -> String {
        switch phase {
        case .recording: return interrupted ? "phone.fill" : "mic.fill"
        case .paused: return "pause.circle.fill"
        case .uploading: return "icloud.and.arrow.up"
        case .sent: return "checkmark.circle.fill"
        case .failed, .startFailed: return "exclamationmark.triangle.fill"
        case .idle: return "mic.fill"
        }
    }

    static func color(_ phase: RecordingState.Phase, interrupted: Bool) -> Color {
        switch phase {
        case .recording: return interrupted ? .orange : .red
        case .paused: return .orange
        case .sent: return .green
        case .failed, .startFailed: return .red
        case .uploading: return .blue
        case .idle: return .red
        }
    }

    static func title(_ phase: RecordingState.Phase, interrupted: Bool) -> String {
        switch phase {
        case .recording: return interrupted ? "Paused for a call" : "Recording"
        case .paused: return "Paused"
        case .uploading: return "Sending to Speakr"
        case .sent: return "Sent to Speakr"
        case .failed: return "Not sent"
        case .startFailed: return "Could not start"
        case .idle: return "Talaria"
        }
    }
}

/// A white symbol on a filled circle: the recorder's button look at every size.
struct RoundActionLabel: View {
    let action: RecorderStyle.Action
    let diameter: CGFloat

    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(action.color.gradient))
            .contentShape(Circle())
            .accessibilityLabel(action.name)
    }
}
