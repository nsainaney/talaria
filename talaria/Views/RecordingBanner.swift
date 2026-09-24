import SwiftUI

/// A strip under the navigation bar while a Speakr recording is running or just finished.
struct RecordingBanner: View {
    @Environment(AppModel.self) private var model
    private let rec = BackgroundRecorder.shared

    var body: some View {
        let s = rec.state
        if s.phase != .idle {
            HStack(spacing: 10) {
                Image(systemName: icon(s)).foregroundStyle(color(s))
                    .symbolEffect(.pulse, isActive: s.phase == .recording && !s.interrupted)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title(s)).font(.footnote.weight(.semibold))
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
                if s.phase == .recording {
                    Button { try? rec.pause() } label: { Image(systemName: "pause.fill") }
                } else if s.phase == .paused {
                    Button { Task { try? await rec.resume() } } label: { Image(systemName: "record.fill").foregroundStyle(.red) }
                }
                if s.isActive {
                    Button { Task { try? await rec.stop() } } label: { Image(systemName: "stop.fill") }
                } else if s.phase != .uploading {
                    if let id = s.speakrRecordingId, let client = model.settings.speakr {
                        Link(destination: client.pageURL(id: id)) { Image(systemName: "arrow.up.right.square") }
                    }
                    Button { rec.clear() } label: { Image(systemName: "xmark") }
                }
            }
            .buttonStyle(.borderless)
            .font(.body)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func icon(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "phone.fill" : "record.circle"
        case .paused: return "pause.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .sent: return "checkmark.circle.fill"
        case .failed, .startFailed: return "exclamationmark.triangle.fill"
        case .idle: return ""
        }
    }

    private func color(_ s: RecordingState) -> Color {
        switch s.phase {
        case .recording: return s.interrupted ? .orange : .red
        case .paused: return .orange
        case .uploading: return .secondary
        case .sent: return .green
        case .failed, .startFailed: return .red
        case .idle: return .secondary
        }
    }

    private func title(_ s: RecordingState) -> String {
        switch s.phase {
        case .recording: return s.interrupted ? "Paused for a call, resumes after" : "Recording for Speakr"
        case .paused: return "Recording paused"
        case .uploading: return "Sending to Speakr…"
        case .sent: return "Recording sent"
        case .failed: return "Recording not sent"
        case .startFailed: return "Recording could not start"
        case .idle: return ""
        }
    }
}
