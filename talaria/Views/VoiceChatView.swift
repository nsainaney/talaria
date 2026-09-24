import SwiftUI
import MarkdownUI

/// Voice mode for a chat: a status line with the model pill, the last exchange (your words as they
/// are understood, Hermes's reply rendered), and one big Pause. Back leaves to the inbox; the
/// pencil in the title bar switches the same conversation back to text.
struct VoiceChatView: View {
    @Environment(AppModel.self) private var model
    @State private var showModel = false

    var body: some View {
        let voice = model.voice
        VStack(spacing: 0) {
            status(voice)
            exchange(voice)
                .opacity(voice.isPaused ? 0.55 : 1)
            Button {
                if voice.isPaused { voice.resume() } else { voice.pause() }
            } label: {
                RoundActionLabel(action: voice.isPaused ? .resume : .pause, diameter: 104)
            }
            .buttonStyle(.plain)
            .padding(.top, 14).padding(.bottom, 28)
        }
        .sheet(isPresented: $showModel) { ModelPickerView() }
        .animation(.snappy, value: voice.state)
        .animation(.snappy, value: voice.isPaused)
    }

    // MARK: Status

    private func status(_ v: VoiceController) -> some View {
        let (text, color) = statusText(v)
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 4).scaleEffect(1.8))
                    .symbolEffect(.pulse, isActive: v.state == .listening && !v.isPaused)
                Text(text).font(.footnote.weight(.semibold)).foregroundStyle(color).lineLimit(1)
                Spacer(minLength: 12)
                modelPill
            }
            if let e = v.error {
                Text(e).font(.caption2).foregroundStyle(Theme.rec).lineLimit(2)
            } else if let e = v.serverVoiceError {
                Text("Server voice unavailable, using the phone's: \(e)").font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.top, 4).padding(.bottom, 6).padding(.horizontal, 16)
    }

    private func statusText(_ v: VoiceController) -> (String, Color) {
        if v.isPaused { return ("Paused", .secondary) }
        switch v.answering {
        case .approval: return ("Say allow, always, or deny", Theme.accent)
        case .clarify: return ("Hermes is asking", Theme.accent)
        case .none: break
        }
        switch v.state {
        case .idle: return ("Voice off", .secondary)
        case .listening: return ("Listening", Theme.rec)
        case .thinking: return ("Hermes is thinking…", .secondary)
        case .speaking: return (v.isPreparingVoice ? "Getting the voice ready…" : "Hermes is speaking", Theme.accent)
        }
    }

    // MARK: The last exchange

    private func exchange(_ v: VoiceController) -> some View {
        let items = recentItems
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(items) { item in
                        switch item.kind {
                        case .user:
                            label("You", Theme.accent)
                            Text(item.text).font(.title3).foregroundStyle(Theme.accent).textSelection(.enabled)
                        case .assistant:
                            label("Hermes", .secondary)
                            Markdown(item.text)
                                .markdownTextStyle { FontSize(20) }
                                .markdownTextStyle(\.code) { FontFamilyVariant(.monospaced); FontSize(.em(0.85)); BackgroundColor(Color(.secondarySystemBackground)) }
                                .textSelection(.enabled)
                        case .tool:
                            HStack(spacing: 6) {
                                if item.isStreaming { ProgressView().controlSize(.mini) } else { Image(systemName: "terminal") }
                                Text(item.toolName ?? "tool").font(.caption.monospaced())
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4).glass(8)
                        case .error:
                            Text(item.text).font(.footnote).foregroundStyle(Theme.rec)
                        default:
                            EmptyView()
                        }
                    }
                    if !v.transcript.isEmpty {
                        label("You", Theme.accent)
                        HStack(alignment: .top, spacing: 10) {
                            (Text(v.transcript) + Text(" ▎").foregroundStyle(Theme.accent.opacity(0.7)))
                                .font(.title3).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // Someone else was talking: drop these words before they are sent.
                            Button { v.discardUtterance() } label: {
                                Image(systemName: "xmark")
                                    .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(width: 52, height: 52).glass(26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Don't send this")
                        }
                    } else if items.isEmpty {
                        Text("Say something. Hermes answers out loud and here.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
                .padding(.horizontal, 22).padding(.vertical, 8)
            }
            .onChange(of: model.chat.items.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: v.transcript) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(color).padding(.top, 10)
    }

    /// From the second-to-last thing you said onward, so the previous reply stays for context.
    private var recentItems: [ChatItem] {
        let items = model.chat.items
        let userIdx = items.indices.filter { items[$0].kind == .user }
        let start = userIdx.count >= 2 ? userIdx[userIdx.count - 2] : (userIdx.first ?? items.startIndex)
        return Array(items[start...])
    }

    private var modelPill: some View {
        Button { showModel = true } label: {
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text(model.chat.modelLabel ?? "Model").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline).foregroundStyle(.primary)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .disabled(!model.gateway.isConnected)
    }
}
