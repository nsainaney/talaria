import Foundation
import Observation

@Observable @MainActor
final class AppModel {
    let settings = ServerSettings()
    let chat = ChatStore()
    let skills = SkillsStore()

    var sessions: [HermesSession] = []
    var sessionsError: String?
    var isLoadingSessions = false
    var hasMoreSessions = false
    private let pageSize = 50

    var client: HermesClient? { settings.client }

    init() {
        chat.client = settings.client
    }

    /// Call after settings change or on launch: rebinds the client and refreshes lists.
    func reconnect() async {
        chat.client = settings.client
        await refreshSessions()
        await skills.load(client: settings.client)
    }

    func refreshSessions() async {
        guard let client else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let page = try await client.listSessions(limit: pageSize, offset: 0)
            sessions = page.data
            hasMoreSessions = page.hasMore ?? false
            sessionsError = nil
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func loadMoreSessions() async {
        guard let client, hasMoreSessions, !isLoadingSessions else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            // Offset counts the recency window only; pinned rows are back-filled past it.
            let offset = sessions.filter { $0.pinned != true }.count
            let page = try await client.listSessions(limit: pageSize, offset: offset)
            let known = Set(sessions.map(\.id))
            sessions += page.data.filter { !known.contains($0.id) }
            hasMoreSessions = page.hasMore ?? false
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func rename(_ s: HermesSession, to title: String) async {
        guard let client else { return }
        do {
            try await client.updateSession(id: s.id, fields: ["title": title])
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i].title = title }
            if chat.session?.id == s.id { chat.session?.title = title }
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func togglePin(_ s: HermesSession) async {
        guard let client else { return }
        let pinned = !(s.pinned ?? false)
        do {
            try await client.updateSession(id: s.id, fields: ["pinned": pinned])
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i].pinned = pinned }
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func delete(_ s: HermesSession) async {
        guard let client else { return }
        do {
            try await client.deleteSession(id: s.id)
            sessions.removeAll { $0.id == s.id }
            if chat.session?.id == s.id { chat.startNewChat() }
        } catch {
            sessionsError = error.localizedDescription
        }
    }
}
