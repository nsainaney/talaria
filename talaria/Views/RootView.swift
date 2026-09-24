import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var showSettings = false
    private let recorder = BackgroundRecorder.shared

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            InboxView(path: $path)
                .toolbarVisibility(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top) { connectionBanner }
                .navigationDestination(for: InboxDestination.self) { dest in
                    switch dest {
                    case .chat(let s): ChatScreen(session: s, startVoice: false)
                    case .newChat(let voice): ChatScreen(session: nil, startVoice: voice)
                    }
                }
        }
        .tint(Theme.accent)
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
        .fullScreenCover(isPresented: $model.showRecorder) { RecordingModeView().environment(model) }
        .onChange(of: recorder.state.isActive) { _, active in
            if active { model.showRecorder = true }
        }
        .task {
            if model.settings.isConfigured { await model.connect() } else { showSettings = true }
        }
        .onOpenURL { url in
            // talaria://record from the widget: start recording and show the recorder.
            guard url.scheme == "talaria", url.host() == "record" else { return }
            model.showRecorder = true
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
}
