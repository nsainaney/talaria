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
        VStack(spacing: 24) {
            HStack {
                Spacer()
                if s.isActive {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3) }
                        .accessibilityLabel("Hide")
                }
            }
            .padding(.horizontal)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: icon(s)).foregroundStyle(color(s))
                    .symbolEffect(.pulse, isActive: s.phase == .recording && !s.interrupted)
                Text(title(s)).font(.title3.weight(.semibold))
            }
            timer(s)
                .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit())
            Text(caption(s)).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            controls(s)
        }
        .padding(.bottom, 32)
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

    @ViewBuilder private func controls(_ s: RecordingState) -> some View {
        VStack(spacing: 14) {
            switch s.phase {
            case .recording, .paused:
                if s.phase == .paused {
                    Button { Task { try? await rec.resume() } } label: {
                        Label("Resume", systemImage: "record.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button { try? rec.pause() } label: {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                HStack(spacing: 14) {
                    Button(role: .destructive) { confirmCancel = true } label: {
                        Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { Task { try? await rec.stop() } } label: {
                        Label("Complete", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
            case .uploading:
                ProgressView().controlSize(.large)
            case .sent, .failed, .startFailed, .idle:
                if let id = s.speakrRecordingId, let client = model.settings.speakr {
                    Link(destination: client.pageURL(id: id)) {
                        Label("Open in Speakr", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { rec.clear(); dismiss() } label: {
                    Text("Close").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.extraLarge)
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 24)
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
