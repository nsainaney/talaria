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
            if !attachments.isEmpty { attachmentStrip }
            composer
        }
        .onChange(of: model.chat.session?.id) { _, _ in draft = ""; attachments = [] }
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
                        Text(model.settings.isConfigured ? "Ask Hermes anything. Type / to pick a skill." : "Set your Hermes server in Settings.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    ForEach(chat.items) { item in
                        ChatRow(item: item).id(item.id)
                    }
                    if chat.isRunning && !(chat.items.last?.isStreaming ?? false) {
                        HStack(spacing: 6) { ProgressView(); Text("Working…").font(.caption).foregroundStyle(.secondary) }
                            .padding(.horizontal)
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

    private var slashPopup: some View {
        let query = String(draft.dropFirst()).components(separatedBy: " ").first ?? ""
        let matches = Array(model.skills.filtered(query).prefix(8))
        return Group {
            if !matches.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                            .background(Color(.secondarySystemBackground))
                        }
                    }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button { attachments.remove(at: i) } label: {
                                Image(systemName: "xmark.circle.fill").font(.body)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(2)
                        }
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { showPhotos = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                }
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
            } label: {
                Image(systemName: "plus.circle").font(.title2)
            }
            .disabled(chat.isRunning || !model.settings.isConfigured)
            TextField(chat.isRunning ? "Steer the running turn…" : "Message Hermes", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($composerFocused)
                .autocorrectionDisabled(draft.hasPrefix("/"))
            if chat.isRunning {
                Button { Task { await steerDraft() } } label: {
                    Image(systemName: "arrow.turn.down.right.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { Task { await chat.stop() } } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .tint(.red)
            } else {
                Button { Task { await sendDraft() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) || !model.settings.isConfigured)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func steerDraft() async {
        let text = draft
        draft = ""
        await chat.steer(text)
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
        await chat.send(Self.expandSlash(text, skills: model.skills), images: images, files: files)
    }

    /// `/skill-name rest of message` becomes an explicit skill invocation.
    static func expandSlash(_ text: String, skills: SkillsStore) -> String {
        guard text.hasPrefix("/") else { return text }
        let body = text.dropFirst()
        let name = String(body.prefix { !$0.isWhitespace })
        guard let skill = skills.skill(named: name) else { return text }
        let rest = String(body.dropFirst(name.count))
        return SkillsStore.invocationText(skill: skill, instruction: rest)
    }
}

extension Notification.Name {
    static let invokeSkill = Notification.Name("talaria.invokeSkill")
}
