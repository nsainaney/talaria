import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSkills: Bool
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var showMeeting = false
    @State private var showModelPicker = false
    @FocusState private var composerFocused: Bool

    private var chat: ChatStore { model.chat }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let err = chat.error {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 4)
            }
            if draft.hasPrefix("/") { slashPopup }
            if model.voice.isActive { VoiceBar().padding(.bottom, 6) }
            composer
        }
        .onChange(of: model.chat.session?.id) { _, _ in draft = ""; attachments = [] }
        .task(id: slashQuery) {
            guard let q = slashQuery else { return }
            try? await Task.sleep(for: .milliseconds(150))
            await model.skills.completeCommands(prefix: q, client: model.gateway)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        attachments.append(.image(img))
                    }
                }
                pickerItems = []
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $pickerItems, maxSelectionCount: 4, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                switch Attachment.load(from: url) {
                case .success(let a): attachments.append(a)
                case .failure(let err): chat.error = err.localizedDescription
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { attachments.append(.image($0)) }.ignoresSafeArea()
        }
        .sheet(isPresented: $showMeeting) { MeetingView() }
        .sheet(isPresented: $showModelPicker) { ModelPickerView() }
        .onReceive(NotificationCenter.default.publisher(for: .invokeSkill)) { note in
            guard let name = note.object as? String else { return }
            draft = "/\(name) "
            composerFocused = true
        }
    }

    /// Whether the transcript follows new content. User scrolling away unpins; the arrow button re-pins.
    @State private var isPinned = true
    @State private var distanceFromBottom: CGFloat = 0
    @State private var scrollPhase: ScrollPhase = .idle
    private let pinThreshold: CGFloat = 32

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.items.isEmpty && !chat.isLoadingHistory {
                        Text(model.settings.isConfigured ? "Ask Hermes anything. Type / to pick a skill." : "Sign in to your Hermes dashboard in Settings.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    ForEach(chat.items) { item in
                        ChatRow(item: item).id(item.id)
                    }
                    if chat.isRunning && !(chat.items.last?.isStreaming ?? false) {
                        HStack(spacing: 6) { ProgressView(); Text(chat.statusText ?? "Working…").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            .padding(.horizontal)
                    } else if chat.isRunning, let status = chat.statusText {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                // Negative while bouncing past the end; visibleRect already accounts for insets.
                geo.contentSize.height - geo.visibleRect.maxY
            } action: { _, distance in
                distanceFromBottom = distance
                let userDriven = scrollPhase == .tracking || scrollPhase == .interacting || scrollPhase == .decelerating
                if distance <= pinThreshold {
                    isPinned = true // at the bottom, or bouncing past it
                } else if userDriven {
                    isPinned = false
                }
            }
            .onScrollPhaseChange { _, phase in scrollPhase = phase }
            .overlay { if chat.isLoadingHistory { ProgressView() } }
            .overlay(alignment: .bottomTrailing) {
                if !isPinned {
                    Button {
                        isPinned = true
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                            .shadow(radius: 3)
                    }
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: isPinned)
            .onChange(of: chat.items.last?.text) { _, _ in
                if isPinned { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.items.count) { _, _ in
                if isPinned { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: model.chat.session?.id) { _, _ in
                isPinned = true
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onTapGesture { composerFocused = false }
        }
    }

    /// The command name being typed after `/`, or nil when the draft is not a slash command.
    private var slashQuery: String? {
        guard draft.hasPrefix("/"), !draft.contains(" ") else { return nil }
        return String(draft.dropFirst())
    }

    private var slashPopup: some View {
        let query = String(draft.dropFirst()).components(separatedBy: " ").first ?? ""
        let matches = Array(model.skills.filtered(query).prefix(8))
        let commands = Array(model.skills.commands(matching: query).prefix(6))
        return Group {
            if !matches.isEmpty || !commands.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commands) { cmd in
                            Button { draft = "/\(cmd.name) " } label: {
                                HStack {
                                    Image(systemName: "terminal").font(.caption2).foregroundStyle(.secondary)
                                    Text(cmd.name).font(.body.monospaced())
                                    Text(cmd.description ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        ForEach(matches) { skill in
                            Button { draft = "/\(skill.name) " } label: {
                                HStack {
                                    if model.skills.isPinned(skill) { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                                    Text(skill.name).font(.body.monospaced())
                                    Text(skill.description ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(.thinMaterial)
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { i, attachment in
                    Group {
                        switch attachment {
                        case .image(let img):
                            Image(uiImage: img).resizable().scaledToFill()
                        case .text(let name, _):
                            VStack(spacing: 4) {
                                Image(systemName: "doc.text").font(.title3)
                                Text(name).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemFill))
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        Button { attachments.remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill").font(.body)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(2)
                    }
                }
            }
        }
    }

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    /// Card-style composer: text on top, controls row below (attach, model pill, send/stop).
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty { attachmentStrip }
            TextField(chat.isRunning ? "Queue a message…" : "Message Hermes", text: $draft, axis: .vertical)
                .lineLimit(1...8)
                .font(.title3)
                .focused($composerFocused)
                .autocorrectionDisabled(draft.hasPrefix("/"))
            HStack(spacing: 10) {
                Menu {
                    Button { showPhotos = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    }
                    Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                    if model.settings.voiceEnabled {
                        Divider()
                        Button { showMeeting = true } label: { Label("Record meeting", systemImage: "record.circle") }
                    }
                } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .disabled(chat.isRunning || !model.gateway.isConnected)
                if model.settings.voiceEnabled && !model.voice.isActive {
                    Button { composerFocused = false; Task { await model.voice.start() } } label: {
                        Image(systemName: "mic").font(.body.weight(.medium))
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .disabled(!model.gateway.isConnected)
                    .accessibilityLabel("Talk to Hermes")
                }
                Button { composerFocused = false; showModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(chat.modelLabel ?? "Model").lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline).foregroundStyle(.primary)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .disabled(!model.gateway.isConnected)
                Spacer()
                primaryButton
            }
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color(.separator).opacity(0.5)))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
        .padding(.horizontal, 10).padding(.bottom, 6)
        .background(.clear)
    }

    /// Stop while a turn runs and nothing is typed; otherwise send (queued during a run).
    @ViewBuilder private var primaryButton: some View {
        if chat.isRunning && !hasDraft {
            Button { Task { await chat.stop() } } label: {
                Image(systemName: "stop.fill").font(.body.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.red, in: Circle())
            }
        } else if chat.isRunning {
            Button { Task { await submitWhileRunning(.queue) } } label: { sendGlyph(enabled: true) }
                .contextMenu {
                    Button { Task { await submitWhileRunning(.queue) } } label: { Label("Queue after this turn", systemImage: "text.append") }
                    Button { Task { await submitWhileRunning(.steer) } } label: { Label("Steer the running turn", systemImage: "arrow.turn.down.right") }
                    Button { Task { await submitWhileRunning(.redirect) } } label: { Label("Redirect the running turn", systemImage: "arrow.uturn.forward") }
                    Divider()
                    Button(role: .destructive) { Task { await chat.stop() } } label: { Label("Stop", systemImage: "stop.circle") }
                }
        } else {
            let enabled = hasDraft && model.gateway.isConnected
            Button { Task { await sendDraft() } } label: { sendGlyph(enabled: enabled) }
                .disabled(!enabled)
        }
    }

    private func sendGlyph(enabled: Bool) -> some View {
        Image(systemName: "arrow.up").font(.body.weight(.bold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .frame(width: 40, height: 40)
            .background(enabled ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
            .animation(.easeInOut(duration: 0.15), value: enabled)
    }

    private enum RunningSubmit { case queue, steer, redirect }

    private func submitWhileRunning(_ mode: RunningSubmit) async {
        let text = draft
        draft = ""
        switch mode {
        case .queue: await chat.enqueue(text)
        case .steer: _ = await chat.steer(text)
        case .redirect: await chat.redirect(text)
        }
    }

    private func sendDraft() async {
        let text = draft
        let pending = attachments
        draft = ""
        attachments = []
        var images: [UIImage] = []
        var files: [(name: String, text: String)] = []
        for a in pending {
            switch a {
            case .image(let img): images.append(img)
            case .text(let name, let body): files.append((name, body))
            }
        }
        await chat.send(text, images: images, files: files, skills: model.skills)
    }
}

extension Notification.Name {
    static let invokeSkill = Notification.Name("talaria.invokeSkill")
}
