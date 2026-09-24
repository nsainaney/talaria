import Foundation
import Observation

@Observable @MainActor
final class AppModel {
    let settings = ServerSettings()
    let gateway = GatewayClient()
    let pins = PinStore()
    let chat = ChatStore()
    let skills: SkillsStore
    let voice: VoiceController

    var sessions: [HermesSession] = []
    var sessionsError: String?
    var isLoadingSessions = false
    var serverVersion: String?
    /// The full-screen recorder is showing.
    var showRecorder = false

    init() {
        skills = SkillsStore(pins: pins)
        voice = VoiceController(chat: chat, skills: skills, settings: settings)
        chat.client = gateway
        BackgroundRecorder.shared.willStart = { [weak self] in self?.voice.stop() }
        VoiceChatIntentHost.commands = voice
        gateway.onEvent = { [weak self] e in self?.handle(event: e) }
        gateway.onServerRequest = { [weak self] r in self?.chat.handle(serverRequest: r) ?? false }
        gateway.onResync = { [weak self] sid in Task { await self?.chat.resync(liveId: sid) } }
        chat.onSessionCreated = { [weak self] s in
            guard let self, !self.sessions.contains(where: { $0.id == s.id }) else { return }
            self.sessions.insert(s, at: 0)
        }
        chat.onTitleChanged = { [weak self] storedId, title in
            guard let self else { return }
            if let i = self.sessions.firstIndex(where: { $0.id == storedId }) { self.sessions[i].title = title }
            if self.chat.session?.id == storedId { self.chat.session?.title = title }
        }
    }

    /// Connect (or reconnect after settings change) and load lists once the socket is up.
    func connect() async {
        guard let auth = settings.auth else { gateway.disconnect(); return }
        let wasConnected = gateway.isConnected
        gateway.connect(auth: auth)
        if wasConnected && gateway.isConnected { return } // nothing changed; lists are already loaded
        // Wait briefly for the first connection before loading lists; later reconnects reload via events.
        for _ in 0..<50 where !gateway.isConnected { try? await Task.sleep(for: .milliseconds(200)) }
        guard gateway.isConnected else { return }
        serverVersion = try? await auth.status().version
        await refreshSessions()
        await skills.load(client: gateway)
        if chat.session == nil, let last = chat.lastOpenedSessionId(), let s = sessions.first(where: { $0.id == last }) {
            await chat.open(s)
        }
    }

    func signOut() async {
        voice.stop()
        gateway.disconnect()
        await settings.auth?.logout()
        settings.clearCredentials()
        sessions = []
        chat.startNewChat()
    }

    private func handle(event e: GatewayEvent) {
        switch e.type {
        case "sessions.changed":
            Task { await refreshSessions() }
        default:
            chat.handle(event: e)
        }
    }

    func refreshSessions() async {
        guard gateway.isConnected else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let r = try await gateway.request("session.list", ["limit": 100], timeout: 60)
            sessions = (r["sessions"] as? [[String: Any]] ?? []).compactMap(HermesSession.init(row:))
            sessionsError = nil
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func rename(_ s: HermesSession, to title: String) async {
        do {
            _ = try await gateway.request("session.title", ["session_id": s.liveId, "title": title], timeout: 30)
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i].title = title }
            if chat.session?.id == s.id { chat.session?.title = title }
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func delete(_ s: HermesSession) async {
        do {
            // A live session must be closed before the store lets it go.
            _ = try? await gateway.request("session.close", ["session_id": s.liveId], timeout: 30)
            _ = try await gateway.request("session.delete", ["session_id": s.id], timeout: 30)
            sessions.removeAll { $0.id == s.id }
            chat.forget(sessionLiveId: s.liveId)
            if chat.session?.id == s.id { chat.startNewChat() }
        } catch {
            sessionsError = error.localizedDescription
        }
    }
}
