import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen presence during a voice chat with Hermes: what it is doing,
/// how long it has run, and Pause/Resume and End.
struct VoiceChatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceChatActivityAttributes.self) { context in
            LockScreenVoiceChatView(state: context.state, startedAt: context.attributes.startedAt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(VoiceChatStyle.title(context.state.phase), systemImage: VoiceChatStyle.icon(context.state.phase))
                        .font(.headline).foregroundStyle(VoiceChatStyle.color(context.state.phase)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VoiceChatButtons(phase: context.state.phase, diameter: 40)
                }
            } compactLeading: {
                Image(systemName: VoiceChatStyle.icon(context.state.phase)).foregroundStyle(VoiceChatStyle.color(context.state.phase))
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).font(.caption.monospacedDigit()).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: VoiceChatStyle.icon(context.state.phase)).foregroundStyle(VoiceChatStyle.color(context.state.phase))
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

struct LockScreenVoiceChatView: View {
    @Environment(\.activityFamily) private var family
    let state: VoiceChatActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        if family == .small {
            watch
        } else {
            phone.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var heading: String { state.title ?? "Voice chat" }

    private var watch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: VoiceChatStyle.icon(state.phase)).foregroundStyle(VoiceChatStyle.color(state.phase))
                Text(VoiceChatStyle.title(state.phase)).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Text(startedAt, style: .timer).font(.headline.monospacedDigit())
            }
            VoiceChatButtons(phase: state.phase, diameter: 34).frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private var phone: some View {
        HStack(spacing: 12) {
            Image(systemName: VoiceChatStyle.icon(state.phase)).font(.title2).foregroundStyle(VoiceChatStyle.color(state.phase))
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.headline).lineLimit(1)
                Text(VoiceChatStyle.title(state.phase)).font(.subheadline).foregroundStyle(VoiceChatStyle.color(state.phase)).lineLimit(1)
            }
            Spacer(minLength: 4)
            VoiceChatButtons(phase: state.phase, diameter: 40)
        }
    }
}

/// Pause or Resume, then End: the same round buttons as the recorder's.
struct VoiceChatButtons: View {
    let phase: VoiceChatState.Phase
    let diameter: CGFloat

    var body: some View {
        HStack(spacing: diameter * 0.3) {
            if phase == .paused {
                Button(intent: ResumeVoiceChatIntent()) { RoundActionLabel(action: .resume, diameter: diameter) }
            } else {
                Button(intent: PauseVoiceChatIntent()) { RoundActionLabel(action: .pause, diameter: diameter) }
            }
            if phase == .speaking {
                Button(intent: ShushVoiceChatIntent()) { RoundActionLabel(action: .shush, diameter: diameter) }
            }
            Button(intent: EndVoiceChatIntent()) { RoundActionLabel(action: .end, diameter: diameter) }
        }
        .buttonStyle(.plain)
    }
}
