import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen presence while a recording runs.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenRecordingView(state: context.state)
                .padding(.horizontal, 16).padding(.vertical, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ActivityGlyphs.title(context.state), systemImage: ActivityGlyphs.icon(context.state))
                        .font(.headline).foregroundStyle(ActivityGlyphs.color(context.state))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: context.state).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let m = context.state.message, !context.state.phase.isActive {
                        Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        ActivityButtons(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: ActivityGlyphs.icon(context.state)).foregroundStyle(ActivityGlyphs.color(context.state))
            } compactTrailing: {
                ActivityTimer(state: context.state).font(.caption.monospacedDigit()).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: ActivityGlyphs.icon(context.state)).foregroundStyle(ActivityGlyphs.color(context.state))
            }
        }
    }
}

struct LockScreenRecordingView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ActivityGlyphs.icon(state)).font(.title2).foregroundStyle(ActivityGlyphs.color(state))
            VStack(alignment: .leading, spacing: 2) {
                Text(ActivityGlyphs.title(state)).font(.headline)
                if let m = state.message, !state.phase.isActive {
                    Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    ActivityTimer(state: state).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if state.phase.isActive {
                ActivityButtons(state: state)
            }
        }
    }
}

struct ActivityTimer: View {
    let state: RecordingActivityAttributes.ContentState
    var body: some View {
        if state.phase == .recording, let start = state.timerStart, !state.interrupted {
            Text(start, style: .timer)
        } else {
            Text(RecordingState.stamp(state.recorded))
        }
    }
}

struct ActivityButtons: View {
    let state: RecordingActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            if state.phase == .recording {
                Button(intent: PauseRecordingIntent()) { Image(systemName: "pause.fill") }
            } else if state.phase == .paused {
                Button(intent: ResumeRecordingIntent()) { Image(systemName: "record.fill") }.tint(.red)
            }
            if state.phase.isActive {
                Button(intent: StopRecordingIntent()) { Image(systemName: "stop.fill") }.tint(.red)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

extension RecordingState.Phase {
    var isActive: Bool { self == .recording || self == .paused }
}

enum ActivityGlyphs {
    static func icon(_ s: RecordingActivityAttributes.ContentState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "phone.fill" : "record.circle"
        case .paused: return "pause.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .sent: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "mic.fill"
        }
    }

    static func color(_ s: RecordingActivityAttributes.ContentState) -> Color {
        switch s.phase {
        case .recording: return s.interrupted ? .orange : .red
        case .paused: return .orange
        case .sent: return .green
        case .failed: return .red
        case .uploading, .idle: return .secondary
        }
    }

    static func title(_ s: RecordingActivityAttributes.ContentState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "On a call, resumes after" : "Recording"
        case .paused: return "Paused"
        case .uploading: return "Sending to Speakr…"
        case .sent: return "Sent to Speakr"
        case .failed: return "Not sent"
        case .idle: return "Recorder"
        }
    }
}
