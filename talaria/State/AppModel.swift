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
    let tasks: TasksStore

    var sessions: [HermesSession] = []
    /// Sessions live in the gateway process right now (open in the dashboard, the TUI, a
    /// messaging gateway, a worker), keyed by stored id: their live id and status. The server
    /// refuses to delete these until they are closed.
    var liveElsewhere: [String: (liveId: String, status: String)] = [:]
    var sessionsError: String?
    var isLoadingSessions = false
    var serverVersion: String?
    /// The full-screen recorder is showing.
    var showRecorder = false

    init() {
        skills = SkillsStore(pins: pins)
        voice = VoiceController(chat: chat, skills: skills, settings: settings)
        tasks = TasksStore(settings: settings)
        chat.client = gateway
        BackgroundRecorder.shared.willStart = { [weak self] in self?.voice.stop() }
        VoiceChatIntentHost.commands = voice
        gateway.onEvent = { [weak self] e in self?.handle(event: e) }
        gateway.onServerRequest = { [weak self] r in self?.chat.handle(serverRequest: r) ?? false }
        gateway.onResync = { [weak self] sid in Task { await self?.chat.resync(liveId: sid) } }
        gateway.onConnected = { [weak self] in Task { await self?.connected() } }
        gateway.onOpenRequests = { [weak self] sid, open in self?.chat.reconcileRequests(session: sid, open: open) }
        gateway.onServerRestart = { [weak self] in self?.chat.dropRequests() }
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

    /// Connect, or reconnect after a settings change. The lists load when the socket comes up.
    func connect() async {
        guard let auth = settings.auth else { gateway.disconnect(); return }
        gateway.connect(auth: auth)
    }

    /// The socket is up, for the first time or after a drop: reload what may have changed
    /// meanwhile, however long the connection took.
    private func connected() async {
        serverVersion = try? await settings.auth?.status().version
        await refreshSessions()
        await skills.load(client: gateway)
        if chat.needsOpen {
            await chat.reopenIfNeeded()
        } else if chat.session == nil, let last = chat.lastOpenedSessionId(), let s = sessions.first(where: { $0.id == last }) {
            await chat.open(s)
        }
    }

    /// The app is in the foreground again: check the socket, and if it held, catch up on the
    /// session list. A socket that did not answer reconnects and reloads through `connected()`.
    func foreground() {
        Task { if await gateway.wake() { await refreshSessions() } }
    }

    /// The chat a live session id belongs to, to name it on a request sheet.
    func sessionTitle(live id: String?) -> String? {
        guard let id else { return nil }
        if let s = chat.session, s.liveId == id || s.id == id { return s.displayTitle }
        let stored = liveElsewhere.first { $0.value.liveId == id }?.key
        return sessions.first { $0.liveId == id || $0.id == id || $0.id == stored }?.displayTitle
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
            if let a = try? await gateway.request("session.active_list", [:], timeout: 30) {
                var live: [String: (liveId: String, status: String)] = [:]
                for row in a["sessions"] as? [[String: Any]] ?? [] {
                    guard let key = row["session_key"] as? String, let id = row["id"] as? String else { continue }
                    live[key] = (id, row["status"] as? String ?? "live")
                }
                liveElsewhere = live
            }
            sessionsError = nil
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    /// A new chat that opens with a message already sent (Start on a card, Why on an ignore).
    /// Returns the session so the caller can push it; nil when the send failed.
    func startChat(_ text: String, file: (name: String, text: String)?, title: String?) async -> HermesSession? {
        voice.stop()
        chat.startNewChat()
        await chat.send(text, files: file.map { [$0] } ?? [], skills: skills)
        guard let s = chat.session else { return nil }
        if let title, !title.isEmpty { await rename(s, to: title) }
        return chat.session ?? s
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
            try await deleteRow(s)
            // A compacted conversation is a chain of rows; the list shows the newest with the
            // root's start time. Deleting one link exposes the previous one under the same start
            // time, so keep deleting until nothing with that start time comes back.
            var last = s
            for _ in 0..<60 {
                await refreshSessions()
                guard let start = last.startedAt,
                      let ghost = sessions.first(where: { $0.id != last.id && $0.startedAt == start && $0.source == last.source }) else { break }
                try await deleteRow(ghost)
                last = ghost
            }
            sessionsError = nil
        } catch {
            sessionsError = "Could not delete: " + error.localizedDescription
        }
    }

    /// Live in another client (not the chat open here).
    func isLiveElsewhere(_ s: HermesSession) -> Bool {
        guard let live = liveElsewhere[s.id] else { return false }
        return live.liveId != chat.session?.liveId
    }

    private func deleteRow(_ s: HermesSession) async throws {
        // A live session must be closed before the store lets it go; use the id the gateway
        // knows it by, which is not the stored id when another client opened it.
        let liveId = liveElsewhere[s.id]?.liveId ?? s.liveId
        _ = try? await gateway.request("session.close", ["session_id": liveId], timeout: 30)
        _ = try await gateway.request("session.delete", ["session_id": s.id], timeout: 30)
        sessions.removeAll { $0.id == s.id }
        liveElsewhere[s.id] = nil
        chat.forget(s)
        if chat.session?.id == s.id { chat.startNewChat() }
    }
}
