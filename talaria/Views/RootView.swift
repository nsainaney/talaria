import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showSidebar = false
    @State private var showSkills = false
    @State private var showSettings = false
    @State private var showRecording = false
    private let recorder = BackgroundRecorder.shared

    var body: some View {
        NavigationStack {
            ChatView(showSkills: $showSkills)
                .navigationTitle(model.chat.session?.displayTitle ?? "New chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { withAnimation(.snappy) { showSidebar.toggle() } } label: {
                            Image(systemName: "sidebar.left")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showSkills = true } label: { Image(systemName: "sparkles") }
                        Button { model.chat.startNewChat() } label: { Image(systemName: "square.and.pencil") }
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 0) { connectionBanner; RecordingBanner() }
                }
        }
        .overlay { sidebarOverlay }
        .sheet(isPresented: $showSkills) { SkillsView() }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await model.connect() } }) { SettingsView() }
        .sheet(item: approvalBinding) { approval in
            ApprovalView(request: approval)
                .interactiveDismissDisabled()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: clarifyBinding) { clarify in
            ClarifyView(request: clarify)
                .interactiveDismissDisabled()
                .presentationDetents([.medium, .large])
        }
        .task {
            if model.settings.isConfigured { await model.connect() } else { showSettings = true }
        }
        .fullScreenCover(isPresented: $showRecording) { RecordingModeView().environment(model) }
        .onChange(of: recorder.state.isActive) { _, active in
            if active { showRecording = true }
        }
        .onOpenURL { url in
            // talaria://record from the widget: start recording and enter recording mode.
            guard url.scheme == "talaria", url.host() == "record" else { return }
            showRecording = true
            if !recorder.state.isActive { Task { try? await recorder.start() } }
        }
    }

    /// A one-line banner while the socket is down; hidden once connected.
    @ViewBuilder private var connectionBanner: some View {
        switch model.gateway.state {
        case .connected, .disconnected: EmptyView()
        case .connecting: banner("Connecting…", .secondary)
        case .reconnecting(let n): banner("Reconnecting (\(n))…", .orange)
        case .failed(let why): banner(why, .red)
        }
    }

    private func banner(_ text: String, _ color: Color) -> some View {
        Text(text).font(.footnote).foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 4).background(.bar)
    }

    private var approvalBinding: Binding<ApprovalRequest?> {
        Binding(get: { model.chat.pendingApproval }, set: { if $0 == nil { model.chat.pendingApproval = nil } })
    }

    private var clarifyBinding: Binding<ClarifyRequest?> {
        Binding(get: { model.chat.pendingClarify }, set: { if $0 == nil { model.chat.pendingClarify = nil } })
    }

    @ViewBuilder private var sidebarOverlay: some View {
        if showSidebar {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { showSidebar = false } }
                SessionsSidebar { session in
                    withAnimation(.snappy) { showSidebar = false }
                    if let session { Task { await model.chat.open(session) } } else { model.chat.startNewChat() }
                }
                .frame(width: 300)
                .background(.regularMaterial)
                .transition(.move(edge: .leading))
            }
            .zIndex(1)
        }
    }
}
