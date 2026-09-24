import SwiftUI

/// A chat, pushed from the inbox. The title is edited in place; the ellipsis holds the chat's
/// settings; the waveform switches the same conversation to voice, the pencil back to text.
struct ChatScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: HermesSession?
    let startVoice: Bool
    @State private var showSkills = false
    @State private var showModel = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private var current: HermesSession? { model.chat.session ?? session }

    var body: some View {
        ChatView()
            .background(GlassBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { showSkills = true } label: { Label("Skills for this chat", systemImage: "sparkles") }
                        Button { showModel = true } label: { Label("Model · \(model.chat.modelLabel ?? "choose")", systemImage: "cpu") }
                        if let s = current {
                            Button { model.pins.toggleSession(s.id) } label: {
                                Label(model.pins.isSessionPinned(s.id) ? "Unpin" : "Pin", systemImage: model.pins.isSessionPinned(s.id) ? "pin.slash" : "pin")
                            }
                            Divider()
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete chat", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button {
                        if model.voice.isActive { model.voice.stop() } else { Task { await model.voice.start() } }
                    } label: {
                        Image(systemName: model.voice.isActive ? "pencil" : "waveform")
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(!model.gateway.isConnected || !model.settings.voiceEnabled)
                    .accessibilityLabel(model.voice.isActive ? "Switch to text" : "Switch to voice")
                }
            }
            .task {
                if let session {
                    if model.chat.session?.id != session.id { await model.chat.open(session) }
                } else if model.chat.session != nil {
                    model.chat.startNewChat()
                }
                if startVoice, !model.voice.isActive { await model.voice.start() }
            }
            .onDisappear { model.voice.stop() }
            .sheet(isPresented: $showSkills) { SkillsView() }
            .sheet(isPresented: $showModel) { ModelPickerView() }
            .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let s = current { Task { await model.delete(s); dismiss() } }
                }
            }
    }

    @ViewBuilder private var titleView: some View {
        if editingTitle {
            TextField("Title", text: $titleDraft)
                .font(.headline).multilineTextAlignment(.center)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { was, now in if was && !now { commitTitle() } }
                .frame(maxWidth: 220)
        } else {
            Button {
                guard current != nil else { return }
                titleDraft = current?.title ?? current?.displayTitle ?? ""
                editingTitle = true
                titleFocused = true
            } label: {
                Text(current?.displayTitle ?? "New chat").font(.headline).lineLimit(1).foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitTitle() {
        editingTitle = false
        let t = titleDraft.trimmingCharacters(in: .whitespaces)
        if let s = current, !t.isEmpty, t != s.title { Task { await model.rename(s, to: t) } }
    }
}
