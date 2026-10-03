import AppIntents
import SwiftUI
import WidgetKit

nonisolated struct RecorderEntry: TimelineEntry {
    let date: Date
    let state: RecordingState
    var voice = VoiceChatState()
}

nonisolated struct RecorderProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecorderEntry {
        RecorderEntry(date: .now, state: RecordingState(micGranted: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (RecorderEntry) -> Void) {
        completion(context.isPreview ? RecorderEntry(date: .now, state: RecordingState(micGranted: true))
                                     : RecorderEntry(date: .now, state: RecordingState.load(), voice: VoiceChatState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecorderEntry>) -> Void) {
        // The app reloads this timeline whenever the recorder's state changes.
        completion(Timeline(entries: [RecorderEntry(date: .now, state: RecordingState.load(), voice: VoiceChatState.load())], policy: .never))
    }
}

/// Home Screen and Lock Screen widget: start a voice chat with Hermes or a recording; while
/// recording, pause, resume, complete or cancel it.
struct RecorderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecordingShared.widgetKind, provider: RecorderProvider()) { entry in
            RecorderWidgetView(state: entry.state, voice: entry.voice)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talaria")
        .description("Start a voice chat with Hermes, or record audio that goes to Speakr for transcription.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct RecorderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let state: RecordingState
    var voice = VoiceChatState()

    /// A voice chat is mirrored only while no recording runs; the recorder owns the microphone.
    private var voiceShowing: Bool { voice.isActive && !state.isActive && state.phase != .uploading }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: home
        }
    }

    // MARK: Voice chat: status and timer, then Pause/Resume and End.

    private var voiceHome: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: VoiceChatStyle.icon(voice.phase)).foregroundStyle(VoiceChatStyle.color(voice.phase))
                Text(VoiceChatStyle.title(voice.phase)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let start = voice.startedAt {
                    Text(start, style: .timer).font(.subheadline.weight(.medium).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
            VoiceChatButtons(phase: voice.phase, diameter: 44)
            if let t = voice.title {
                Text(t).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Home Screen: title, then the mic, or the timer with Cancel/Complete and Pause/Resume.

    @ViewBuilder private var home: some View {
        if voiceShowing { voiceHome } else { recorderHome }
    }

    private var recorderHome: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: RecorderStyle.icon(state.phase, interrupted: state.interrupted))
                    .foregroundStyle(RecorderStyle.color(state.phase, interrupted: state.interrupted))
                Text(state.isActive ? RecorderStyle.title(state.phase, interrupted: state.interrupted) : "Talaria")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if state.isActive {
                    timer.font(.subheadline.weight(.medium).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
            switch state.phase {
            case .recording, .paused:
                RecorderButtons(state: state, diameter: 36)
            case .uploading:
                Label("Sending to Speakr…", systemImage: "icloud.and.arrow.up").font(.footnote).foregroundStyle(.secondary)
            case .idle, .sent, .failed, .startFailed:
                StartButtons(diameter: family == .systemSmall ? 52 : 64, captions: note == nil)
                if let note {
                    Text(note).font(.caption2).foregroundStyle(state.phase == .sent ? Color.secondary : Color.red)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var timer: some View {
        if state.phase == .recording, let start = state.timerStart, !state.interrupted {
            Text(start, style: .timer)
        } else {
            Text(RecordingState.stamp(state.recorded))
        }
    }

    /// A line under the mic after a stop or a failure; nothing when idle.
    private var note: String? {
        switch state.phase {
        case .sent: return state.speakrRecordingId.map { "Sent to Speakr as #\($0)" } ?? "Sent to Speakr"
        case .failed, .startFailed: return state.message
        default: return nil
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if voiceShowing {
                if voice.phase == .paused {
                    Button(intent: ResumeVoiceChatIntent()) { Image(systemName: RecorderStyle.Action.resume.symbol).font(.title2) }
                } else {
                    Button(intent: PauseVoiceChatIntent()) { Image(systemName: RecorderStyle.Action.pause.symbol).font(.title2) }
                }
            } else if state.isActive {
                Button(intent: StopRecordingIntent()) { Image(systemName: RecorderStyle.Action.complete.symbol).font(.title2) }
            } else if state.phase == .uploading {
                Image(systemName: "icloud.and.arrow.up").font(.title2)
            } else {
                Link(destination: RecordingShared.recordURL) { Image(systemName: RecorderStyle.Action.record.symbol).font(.title2) }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var rectangular: some View {
        if voiceShowing { voiceRectangular } else { recorderRectangular }
    }

    private var voiceRectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.title ?? "Voice chat").font(.headline).lineLimit(1)
                Text(VoiceChatStyle.title(voice.phase)).font(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
            VoiceChatButtons(phase: voice.phase, diameter: 30)
        }
    }

    private var recorderRectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isActive ? RecorderStyle.title(state.phase, interrupted: state.interrupted) : "Talaria")
                    .font(.headline).lineLimit(1)
                if state.isActive || state.phase == .uploading {
                    timer.font(.body.monospacedDigit())
                } else if let note {
                    Text(note).font(.caption2).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if state.isActive {
                RecorderButtons(state: state, diameter: 30, singleRow: true)
            } else if state.phase != .uploading {
                StartButtons(diameter: 30, captions: false)
            }
        }
    }
}

/// Nothing running: Voice chat and Record, side by side, opening the app into either.
struct StartButtons: View {
    let diameter: CGFloat
    var captions = true

    var body: some View {
        HStack(spacing: diameter * 0.45) {
            Link(destination: RecordingShared.voiceChatURL) { button(.voiceChat) }
            Link(destination: RecordingShared.recordURL) { button(.record) }
        }
    }

    private func button(_ action: RecorderStyle.Action) -> some View {
        VStack(spacing: 4) {
            RoundActionLabel(action: action, diameter: diameter)
            if captions {
                Text(action.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// While a recording runs: Cancel and Complete, then Pause or Resume. Or all three in one row.
struct RecorderButtons: View {
    let state: RecordingState
    let diameter: CGFloat
    var singleRow = false

    var body: some View {
        Group {
            if singleRow {
                HStack(spacing: diameter * 0.3) { cancel; pauseResume; complete }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: diameter * 0.6) { cancel; complete }
                    pauseResume
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var cancel: some View {
        Button(intent: CancelRecordingIntent()) { RoundActionLabel(action: .cancel, diameter: diameter) }
    }

    private var complete: some View {
        Button(intent: StopRecordingIntent()) { RoundActionLabel(action: .complete, diameter: diameter) }
    }

    @ViewBuilder private var pauseResume: some View {
        if state.phase == .paused {
            Button(intent: ResumeRecordingIntent()) { RoundActionLabel(action: .resume, diameter: diameter) }
        } else {
            Button(intent: PauseRecordingIntent()) { RoundActionLabel(action: .pause, diameter: diameter) }
        }
    }
}
