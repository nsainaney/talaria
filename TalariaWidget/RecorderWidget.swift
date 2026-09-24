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

/// Home Screen and Lock Screen widget: start a recording, pause, resume or stop it.
struct RecorderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecordingShared.widgetKind, provider: RecorderProvider()) { entry in
            RecorderWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recorder")
        .description("Record audio and send it to Speakr for transcription when you stop.")
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

    // MARK: Home Screen: title, then one big Record button, or the timer with Pause/Resume and Stop.

    private var home: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").foregroundStyle(.red)
                Text("Talaria").font(.headline)
                Spacer(minLength: 0)
                if state.isActive {
                    Image(systemName: RecorderGlyphs.icon(state)).foregroundStyle(RecorderGlyphs.color(state)).font(.caption)
                    timer.font(.subheadline.weight(.medium).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
            switch state.phase {
            case .recording, .paused:
                RecorderButtons(state: state, compact: false)
            case .uploading:
                Label("Sending to Speakr…", systemImage: "icloud.and.arrow.up").font(.footnote).foregroundStyle(.secondary)
            case .idle, .sent, .failed, .startFailed:
                RecordButton(size: family == .systemSmall ? 64 : 72)
                if let note = RecorderGlyphs.note(state) {
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

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if state.isActive {
                Button(intent: StopRecordingIntent()) { Image(systemName: "stop.fill").font(.title2) }
            } else if state.phase == .uploading {
                Image(systemName: "icloud.and.arrow.up").font(.title2)
            } else {
                Button(intent: StartRecordingIntent()) { Image(systemName: "record.circle").font(.title2) }
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isActive ? RecorderGlyphs.title(state) : "Talaria").font(.headline).lineLimit(1)
                if state.isActive || state.phase == .uploading {
                    timer.font(.body.monospacedDigit())
                } else if let note = RecorderGlyphs.note(state) {
                    Text(note).font(.caption2).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if state.isActive {
                RecorderButtons(state: state, compact: true)
            } else if state.phase != .uploading {
                Button(intent: StartRecordingIntent()) { Image(systemName: "record.circle") }
                    .buttonStyle(.bordered).controlSize(.small).tint(.red)
            }
        }
    }
}

/// The big red Record button.
struct RecordButton: View {
    let size: CGFloat

    var body: some View {
        Button(intent: StartRecordingIntent()) {
            ZStack {
                Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 3)
                Circle().fill(.red).padding(6)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record")
    }
}

/// While a recording runs: Cancel and Done, then Pause or Resume. Compact: one row of icons.
struct RecorderButtons: View {
    let state: RecordingState
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) { cancel; pauseResume; done }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 6) { cancel; done }
                    pauseResume
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var cancel: some View {
        Button(intent: CancelRecordingIntent()) { label("Cancel", "xmark") }
    }

    private var done: some View {
        Button(intent: StopRecordingIntent()) { label("Done", "checkmark") }.tint(.red)
    }

    @ViewBuilder private var pauseResume: some View {
        if state.phase == .paused {
            Button(intent: ResumeRecordingIntent()) { label("Resume", "record.fill") }
        } else {
            Button(intent: PauseRecordingIntent()) { label("Pause", "pause.fill") }
        }
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            .font(.caption.weight(.medium))
            .frame(maxWidth: compact ? nil : .infinity)
    }
}

/// Type-erased label style so one modifier can pick either.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

enum RecorderGlyphs {
    static func icon(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "phone.fill" : "record.circle"
        case .paused: return "pause.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .sent: return "checkmark.circle.fill"
        case .failed, .startFailed: return "exclamationmark.triangle.fill"
        case .idle: return "mic.fill"
        }
    }

    static func color(_ s: RecordingState) -> Color {
        switch s.phase {
        case .recording: return s.interrupted ? .orange : .red
        case .paused: return .orange
        case .sent: return .green
        case .failed, .startFailed: return .red
        case .uploading, .idle: return .secondary
        }
    }

    static func title(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "On a call" : "Recording"
        case .paused: return "Paused"
        case .uploading: return "Sending…"
        case .sent: return "Sent to Speakr"
        case .failed: return "Not sent"
        case .startFailed: return "Couldn't start"
        case .idle: return "Recorder"
        }
    }

    /// A line under the Record button after a stop or a failure; nothing when idle.
    static func note(_ s: RecordingState) -> String? {
        switch s.phase {
        case .sent: return s.speakrRecordingId.map { "Sent to Speakr as #\($0)" } ?? "Sent to Speakr"
        case .failed, .startFailed: return s.message
        default: return nil
        }
    }
}
