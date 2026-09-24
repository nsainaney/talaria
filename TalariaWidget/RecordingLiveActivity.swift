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
                    Label(RecorderStyle.title(context.state.phase, interrupted: context.state.interrupted),
                          systemImage: RecorderStyle.icon(context.state.phase, interrupted: context.state.interrupted))
                        .font(.headline)
                        .foregroundStyle(RecorderStyle.color(context.state.phase, interrupted: context.state.interrupted))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: context.state).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let m = context.state.message, !context.state.phase.isActive {
                        Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        ActivityButtons(state: context.state, diameter: 40)
                    }
                }
            } compactLeading: {
                Image(systemName: RecorderStyle.icon(context.state.phase, interrupted: context.state.interrupted))
                    .foregroundStyle(RecorderStyle.color(context.state.phase, interrupted: context.state.interrupted))
            } compactTrailing: {
                ActivityTimer(state: context.state).font(.caption.monospacedDigit()).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: RecorderStyle.icon(context.state.phase, interrupted: context.state.interrupted))
                    .foregroundStyle(RecorderStyle.color(context.state.phase, interrupted: context.state.interrupted))
            }
        }
    }
}

struct LockScreenRecordingView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: RecorderStyle.icon(state.phase, interrupted: state.interrupted))
                .font(.title2)
                .foregroundStyle(RecorderStyle.color(state.phase, interrupted: state.interrupted))
            VStack(alignment: .leading, spacing: 2) {
                Text(RecorderStyle.title(state.phase, interrupted: state.interrupted)).font(.headline)
                if let m = state.message, !state.phase.isActive {
                    Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    ActivityTimer(state: state).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if state.phase.isActive {
                ActivityButtons(state: state, diameter: 40)
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

/// Cancel, Pause/Resume, Complete: the same round buttons as the widget and the app.
struct ActivityButtons: View {
    let state: RecordingActivityAttributes.ContentState
    let diameter: CGFloat

    var body: some View {
        HStack(spacing: diameter * 0.3) {
            Button(intent: CancelRecordingIntent()) { RoundActionLabel(action: .cancel, diameter: diameter) }
            if state.phase == .paused {
                Button(intent: ResumeRecordingIntent()) { RoundActionLabel(action: .resume, diameter: diameter) }
            } else {
                Button(intent: PauseRecordingIntent()) { RoundActionLabel(action: .pause, diameter: diameter) }
            }
            Button(intent: StopRecordingIntent()) { RoundActionLabel(action: .complete, diameter: diameter) }
        }
        .buttonStyle(.plain)
    }
}

extension RecordingState.Phase {
    var isActive: Bool { self == .recording || self == .paused }
}
