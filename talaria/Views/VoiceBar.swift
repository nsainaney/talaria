import SwiftUI

/// Compact status strip shown above the composer while voice mode is on.
struct VoiceBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let voice = model.voice
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: voice.state))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(voice.state == .listening ? Color.accentColor : Color.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: voice.state == .listening || (voice.state == .speaking && !voice.isPreparingVoice))
                    .frame(width: 22)
                Text(label(for: voice)).font(.subheadline.weight(.medium))
                Spacer()
                Button { voice.stop() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel("End voice mode")
            }
            if !voice.transcript.isEmpty {
                Text(voice.transcript).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            if let e = voice.error {
                Text(e).font(.caption).foregroundStyle(.red)
            } else if let e = voice.serverVoiceError {
                Text("Server voice unavailable, using phone voice: \(e)").font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .animation(.snappy, value: voice.state)
    }

    private func icon(for s: VoiceController.State) -> String {
        switch s {
        case .idle: return "mic"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2"
        }
    }

    private func label(for v: VoiceController) -> String {
        switch v.answering {
        case .approval: return "Say allow, always, or deny"
        case .clarify: return "Hermes is asking"
        case .none: break
        }
        switch v.state {
        case .idle: return "Voice off"
        case .listening: return "Listening"
        case .thinking: return "Hermes is working…"
        case .speaking: return v.isPreparingVoice ? "Getting the voice ready…" : "Speaking"
        }
    }
}
