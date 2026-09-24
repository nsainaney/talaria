import SwiftUI

/// A strip under the navigation bar while a Speakr recording is running or just finished.
/// Tapping it opens recording mode.
struct RecordingBanner: View {
    @Environment(AppModel.self) private var model
    private let rec = BackgroundRecorder.shared
    @State private var showRecording = false

    var body: some View {
        let s = rec.state
        if s.phase != .idle {
            HStack(spacing: 10) {
                Image(systemName: RecorderStyle.icon(s.phase, interrupted: s.interrupted))
                    .foregroundStyle(RecorderStyle.color(s.phase, interrupted: s.interrupted))
                    .symbolEffect(.pulse, isActive: s.phase == .recording && !s.interrupted)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(RecorderStyle.title(s.phase, interrupted: s.interrupted)).font(.footnote.weight(.semibold))
                        if s.phase == .recording, let start = s.timerStart, !s.interrupted {
                            Text(start, style: .timer).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        } else if s.isActive {
                            Text(RecordingState.stamp(s.recorded)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if !s.isActive, let m = s.message {
                        Text(m).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if s.isActive {
                    Button { Task { try? await rec.cancel() } } label: { RoundActionLabel(action: .cancel, diameter: 28) }
                    if s.phase == .paused {
                        Button { Task { try? await rec.resume() } } label: { RoundActionLabel(action: .resume, diameter: 28) }
                    } else {
                        Button { try? rec.pause() } label: { RoundActionLabel(action: .pause, diameter: 28) }
                    }
                    Button { Task { try? await rec.stop() } } label: { RoundActionLabel(action: .complete, diameter: 28) }
                } else if s.phase != .uploading {
                    if let id = s.speakrRecordingId, let client = model.settings.speakr {
                        Link(destination: client.pageURL(id: id)) { Image(systemName: "arrow.up.right.square") }
                    }
                    Button { rec.clear() } label: { RoundActionLabel(action: .close, diameter: 28) }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture { showRecording = true }
            .fullScreenCover(isPresented: $showRecording) { RecordingModeView().environment(model) }
        }
    }
}
