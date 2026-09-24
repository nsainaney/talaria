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

    // MARK: Home Screen

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: RecorderGlyphs.icon(state)).foregroundStyle(RecorderGlyphs.color(state))
                Text(RecorderGlyphs.title(state)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            if state.phase == .recording, let start = state.timerStart, !state.interrupted {
                Text(start, style: .timer).font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(.primary)
            } else if state.isActive || state.phase == .uploading {
                Text(RecordingState.stamp(state.recorded)).font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(RecorderGlyphs.subtitle(state)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 3)
            }
            Spacer(minLength: 0)
            RecorderButtons(state: state, compact: family == .systemSmall)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if state.isActive {
                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill").font(.title2)
                }
            } else if state.phase == .uploading {
                Image(systemName: "icloud.and.arrow.up").font(.title2)
            } else {
                Link(destination: RecordingShared.recordURL) {
                    Image(systemName: "record.circle").font(.title2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RecorderGlyphs.title(state)).font(.headline).lineLimit(1)
                if state.phase == .recording, let start = state.timerStart, !state.interrupted {
                    Text(start, style: .timer).font(.body.monospacedDigit())
                } else if state.isActive || state.phase == .uploading {
                    Text(RecordingState.stamp(state.recorded)).font(.body.monospacedDigit())
                } else {
                    Text(RecorderGlyphs.subtitle(state)).font(.caption2).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            RecorderButtons(state: state, compact: true)
        }
    }
}

/// The action buttons for the current phase.
struct RecorderButtons: View {
    let state: RecordingState
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch state.phase {
            case .recording:
                Button(intent: PauseRecordingIntent()) { label("Pause", "pause.fill") }
                Button(intent: StopRecordingIntent()) { label("Stop", "stop.fill") }.tint(.red)
            case .paused:
                Button(intent: ResumeRecordingIntent()) { label("Resume", "record.fill") }.tint(.red)
                Button(intent: StopRecordingIntent()) { label("Stop", "stop.fill") }
            case .uploading:
                EmptyView()
            case .idle, .sent, .failed, .startFailed:
                // iOS refuses to begin recording in the background, so Record opens the app and starts there.
                Link(destination: RecordingShared.recordURL) { label("Record", "record.circle") }.tint(.red)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .small : .regular)
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
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

    static func subtitle(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "Resumes when the call ends" : ""
        case .sent: return s.speakrRecordingId.map { "Recording #\($0) is being transcribed." } ?? "Being transcribed."
        case .failed, .startFailed: return s.message ?? "The audio is saved on this phone."
        case .idle: return "Tap to record. Stop sends it to Speakr."
        default: return ""
        }
    }
}
