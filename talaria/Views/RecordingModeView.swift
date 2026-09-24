import SwiftUI

/// Full-screen recording mode: the timer and large Pause/Resume, Complete and Cancel buttons.
/// Driven by the shared recorder, so it comes back when the app does; "Hide" returns to the chat
/// with the recording still running (the strip under the title bar reopens it).
struct RecordingModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let rec = BackgroundRecorder.shared
    @State private var confirmCancel = false

    var body: some View {
        let s = rec.state
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: 0) {
                // Top third: status and the timer.
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: icon(s)).foregroundStyle(color(s))
                                .symbolEffect(.pulse, isActive: s.phase == .recording && !s.interrupted)
                            Text(title(s)).font(.title3.weight(.semibold))
                        }
                        timer(s)
                            .font(.system(size: 84, weight: .light, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    if s.isActive {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down").font(.title3).padding(12)
                        }
                        .accessibilityLabel("Hide")
                    }
                }
                .frame(height: h / 3)
                // Middle: a line of context.
                Text(caption(s)).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                    .frame(maxHeight: .infinity)
                // Bottom half: two rows of large buttons, a quarter of the screen each.
                controls(s, rowHeight: h / 4)
                    .frame(height: h / 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .confirmationDialog("Discard this recording?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) { Task { try? await rec.cancel() } }
        }
        .onChange(of: s.phase) { _, phase in
            if phase == .idle { dismiss() }
        }
    }

    @ViewBuilder private func timer(_ s: RecordingState) -> some View {
        if s.phase == .recording, let start = s.timerStart, !s.interrupted {
            Text(start, style: .timer)
        } else {
            Text(RecordingState.stamp(s.recorded))
        }
    }

    @ViewBuilder private func controls(_ s: RecordingState, rowHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            switch s.phase {
            case .recording, .paused:
                if s.phase == .paused {
                    bigButton("Resume", "record.fill", .red) { Task { try? await rec.resume() } }
                } else {
                    bigButton("Pause", "pause.fill", .orange) { try? rec.pause() }
                }
                HStack(spacing: 12) {
                    bigButton("Cancel", "xmark", .gray) { confirmCancel = true }
                    bigButton("Complete", "checkmark", .green) { Task { try? await rec.stop() } }
                }
            case .uploading:
                ProgressView().controlSize(.large).frame(maxHeight: .infinity)
            case .sent, .failed, .startFailed, .idle:
                if let id = s.speakrRecordingId, let client = model.settings.speakr {
                    Link(destination: client.pageURL(id: id)) {
                        Label("Open in Speakr", systemImage: "arrow.up.right.square")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                bigButton("Close", "xmark", .gray) { rec.clear(); dismiss() }
            }
        }
    }

    /// A button that fills its row: easy to hit without looking.
    private func bigButton(_ text: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 34, weight: .semibold))
                Text(text).font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .tint(tint)
    }

    private func icon(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "phone.fill" : "mic.fill"
        case .paused: return "pause.circle.fill"
        case .uploading: return "icloud.and.arrow.up"
        case .sent: return "checkmark.circle.fill"
        case .failed, .startFailed: return "exclamationmark.triangle.fill"
        case .idle: return "mic"
        }
    }

    private func color(_ s: RecordingState) -> Color {
        switch s.phase {
        case .recording: return s.interrupted ? .orange : .red
        case .paused: return .orange
        case .sent: return .green
        case .failed, .startFailed: return .red
        case .uploading, .idle: return .secondary
        }
    }

    private func title(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "Paused for a call" : "Recording"
        case .paused: return "Paused"
        case .uploading: return "Sending to Speakr"
        case .sent: return "Sent to Speakr"
        case .failed: return "Not sent"
        case .startFailed: return "Could not start"
        case .idle: return "Recorder"
        }
    }

    private func caption(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording where s.interrupted: return "Recording resumes when the call ends."
        case .recording, .paused:
            return s.speakrConfigured ? "Complete sends the recording to Speakr for transcription. You can leave the app; it keeps recording."
                                      : "Saved on this phone. Set the Speakr server in Settings to have recordings transcribed."
        case .uploading: return "You can leave the app; the upload finishes in the background."
        default: return s.message ?? ""
        }
    }
}
