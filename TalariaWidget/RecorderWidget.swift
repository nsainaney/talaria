import AppIntents
import SwiftUI
import WidgetKit

nonisolated struct RecorderEntry: TimelineEntry {
    let date: Date
    let state: RecordingState
}

nonisolated struct RecorderProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecorderEntry {
        RecorderEntry(date: .now, state: RecordingState(micGranted: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (RecorderEntry) -> Void) {
        completion(RecorderEntry(date: .now, state: context.isPreview ? RecordingState(micGranted: true) : RecordingState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecorderEntry>) -> Void) {
        // The app reloads this timeline whenever the recorder's state changes.
        completion(Timeline(entries: [RecorderEntry(date: .now, state: RecordingState.load())], policy: .never))
    }
}

/// Home Screen and Lock Screen widget: start a recording, pause, resume, complete or cancel it.
struct RecorderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecordingShared.widgetKind, provider: RecorderProvider()) { entry in
            RecorderWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recorder")
        .description("Record audio and send it to Speakr for transcription when you finish.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct RecorderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let state: RecordingState

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: home
        }
    }

    // MARK: Home Screen: title, then the mic, or the timer with Cancel/Complete and Pause/Resume.

    private var home: some View {
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
                Link(destination: RecordingShared.recordURL) {
                    RoundActionLabel(action: .record, diameter: family == .systemSmall ? 64 : 72)
                }
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
            if state.isActive {
                Button(intent: StopRecordingIntent()) { Image(systemName: RecorderStyle.Action.complete.symbol).font(.title2) }
            } else if state.phase == .uploading {
                Image(systemName: "icloud.and.arrow.up").font(.title2)
            } else {
                Link(destination: RecordingShared.recordURL) { Image(systemName: RecorderStyle.Action.record.symbol).font(.title2) }
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangular: some View {
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
                Link(destination: RecordingShared.recordURL) { RoundActionLabel(action: .record, diameter: 30) }
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
