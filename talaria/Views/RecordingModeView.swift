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
                            Image(systemName: RecorderStyle.icon(s.phase, interrupted: s.interrupted)).foregroundStyle(RecorderStyle.color(s.phase, interrupted: s.interrupted))
                                .symbolEffect(.pulse, isActive: s.phase == .recording && !s.interrupted)
                            Text(s.phase == .idle ? "Ready to record" : RecorderStyle.title(s.phase, interrupted: s.interrupted)).font(.title3.weight(.semibold))
                        }
                        timer(s)
                            .font(.system(size: 84, weight: .light, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.title3).padding(12)
                    }
                    .accessibilityLabel("Hide")
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
        .onChange(of: s.phase) { old, phase in
            if phase == .idle, old == .recording || old == .paused { dismiss() } // cancelled
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
        let d = min(rowHeight * 0.72, 124)
        VStack(spacing: 0) {
            switch s.phase {
            case .recording, .paused:
                row(rowHeight) {
                    if s.phase == .paused {
                        round(.resume, d) { Task { try? await rec.resume() } }
                    } else {
                        round(.pause, d) { try? rec.pause() }
                    }
                }
                row(rowHeight) {
                    HStack(spacing: d * 0.6) {
                        round(.cancel, d) { confirmCancel = true }
                        round(.complete, d) { Task { try? await rec.stop() } }
                    }
                }
            case .uploading:
                ProgressView().controlSize(.large).frame(maxHeight: .infinity)
            case .idle, .startFailed:
                row(rowHeight) {
                    round(.record, d) { Task { try? await rec.start() } }
                }
                row(rowHeight) { EmptyView() }
            case .sent, .failed:
                row(rowHeight) {
                    if let id = s.speakrRecordingId, let client = model.settings.speakr {
                        Link(destination: client.pageURL(id: id)) {
                            Label("Open in Speakr", systemImage: "arrow.up.right.square").font(.headline)
                        }
                    }
                }
                row(rowHeight) {
                    round(.close, d) { rec.clear(); dismiss() }
                }
            }
        }
    }

    private func row<V: View>(_ height: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content().frame(maxWidth: .infinity).frame(height: height)
    }

    /// A round icon button, big enough to hit without looking.
    private func round(_ action: RecorderStyle.Action, _ diameter: CGFloat, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { RoundActionLabel(action: action, diameter: diameter) }
            .buttonStyle(.plain)
    }

    private func caption(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording where s.interrupted: return "Recording resumes when the call ends."
        case .recording, .paused:
            return s.speakrConfigured ? "Complete sends the recording to Speakr for transcription. You can leave the app; it keeps recording."
                                      : "Saved on this phone. Set the Speakr server in Settings to have recordings transcribed."
        case .uploading: return "You can leave the app; the upload finishes in the background."
        case .idle: return "Tap the mic to start. Complete sends the recording to Speakr."
        default: return s.message ?? ""
        }
    }
}
