import Foundation
import Observation

/// Tasks: what came in (the context engine's triage list), the Hermes backlog, and what Hermes is
/// doing (the kanban board). Answers are Me (an Apple Reminder), Agent (a card) or Ignore, each
/// recorded as a decision in the context store.
@Observable @MainActor
final class TasksStore {
    private let settings: ServerSettings
    private static let sessionMapKey = "tasks.cardSessions"

    /// The New section: candidates without a decision, in the curated order the store keeps.
    var new: [TriageEntry] = []
    /// Cards not started: triage, todo, scheduled.
    var backlog: [KanbanCard] = []
    /// Cards running, blocked, ready (claimed soon), review.
    var inProgress: [KanbanCard] = []
    /// Done and failed cards from the last week.
    var done: [KanbanCard] = []
    var scanning: ContextClient.Scanning?
    var asOf: Date?
    var error: String?
    var isLoading = false
    /// Card id → the chat session that enriched it (Start), kept on the phone.
    private(set) var cardSessions: [String: String]
    private var streamTask: Task<Void, Never>?
    private var refreshDebounce: Task<Void, Never>?

    init(settings: ServerSettings) {
        self.settings = settings
        cardSessions = UserDefaults.standard.dictionary(forKey: Self.sessionMapKey) as? [String: String] ?? [:]
    }

    var context: ContextClient? { settings.context }
    private var board: String? { settings.kanbanBoard.isEmpty ? nil : settings.kanbanBoard }

    var triageCount: Int { new.count }
    var needsYouCount: Int { inProgress.filter(\.needsYou).count }

    // MARK: Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let triage: ContextClient.Triage? = loadTriage()
        async let cards: [String: [KanbanCard]]? = loadBoard()
        let (t, b) = await (triage, cards)
        if let t {
            new = t.new
            scanning = t.scanning
            asOf = t.asOf
        }
        if let b {
            let all = b.values.flatMap { $0 }
            backlog = all.filter(\.isBacklog).sorted { ($0.priority, $0.createdAt) > ($1.priority, $1.createdAt) }
            inProgress = all.filter(\.isInProgress).sorted { ($0.needsYou ? 0 : 1, $0.startedAt ?? $0.createdAt) < ($1.needsYou ? 0 : 1, $1.startedAt ?? $1.createdAt) }
            let week = Date().addingTimeInterval(-7 * 86400)
            done = all.filter { $0.status == "done" && ($0.completedAt ?? $0.createdAt) > week }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    private func loadTriage() async -> ContextClient.Triage? {
        guard let context else { return nil }
        do {
            let t = try await context.triage()
            error = nil
            return t
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func loadBoard() async -> [String: [KanbanCard]]? {
        guard let auth = settings.auth else { return nil }
        do {
            let b = try await auth.kanbanBoard(board)
            return b
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Follows the context engine's event stream while the Tasks page is open; any triage or kanban
    /// event refreshes the lists after a short pause so bursts collapse into one reload.
    func startLive() {
        stopLive()
        guard let context else { return }
        streamTask = Task { [weak self] in
            var backoff: Double = 1
            while !Task.isCancelled {
                do {
                    for try await event in try context.stream() {
                        backoff = 1
                        guard let self else { return }
                        if event.topic.hasPrefix("hermes/triage") || event.topic.hasPrefix("hermes/events/kanban") {
                            if event.topic == "hermes/triage/scan", let s = ContextClient.Scanning(row: event.data) {
                                self.scanning = event.data["finished_at"] == nil ? s : nil
                            }
                            self.scheduleRefresh()
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    func stopLive() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func scheduleRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: Scan

    func scan() async {
        guard let context else { error = "Sign in to the dashboard in Settings to scan."; return }
        do {
            let id = try await context.scan()
            scanning = ContextClient.Scanning(id: id, total: 0, done: 0, found: 0, skipped: 0, skippedReason: nil)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Answers on an item

    /// Me: an Apple Reminder with the source link, then the decision. The item leaves the list.
    func remind(_ entry: TriageEntry, day: Date, time: DateComponents?, listId: String?) async throws {
        let item = entry.item
        var notes = [item.sourceLine, item.sourceTag]
        if let c = entry.candidate, !c.why.isEmpty { notes.append(c.why) }
        let excerpt = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty { notes.append(String(excerpt.prefix(400))) }
        notes.append("talaria://item/" + (item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id))
        let id = try await RemindersWriter.shared.add(title: entry.title, day: day, time: time, listId: listId,
                                                      url: item.url.flatMap(URL.init(string:)), notes: notes.joined(separator: "\n"))
        try await context?.decide(itemId: item.id, contentHash: item.contentHash, decision: "me", target: "reminder:" + id)
        new.removeAll { $0.id == entry.id }
    }

    /// Agent: a bare card in the backlog (status triage, so nothing starts), then the decision.
    @discardableResult
    func agent(_ entry: TriageEntry) async throws -> KanbanCard {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        let item = entry.item
        var body = ["source: " + (item.url ?? item.sourceLine), "from: " + item.sourceLine, "item: " + item.id, ""]
        if let c = entry.candidate, !c.why.isEmpty { body.append("Why it is here: " + c.why); body.append("") }
        let excerpt = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty { body.append(String(excerpt.prefix(3000))) }
        let card = try await auth.kanbanCreate(board: board, title: entry.title, body: body.joined(separator: "\n"),
                                               assignee: nil, triage: true, idempotencyKey: "talaria:" + item.id)
        try await context?.decide(itemId: item.id, contentHash: item.contentHash, decision: "agent", target: "card:\(card.board.isEmpty ? "current" : card.board):\(card.id)")
        new.removeAll { $0.id == entry.id }
        backlog.insert(card, at: 0)
        return card
    }

    /// Done: it was a real task and it is handled. Leaves the list and teaches the screener.
    func markDone(_ entry: TriageEntry, note: String? = nil) async throws {
        try await context?.decide(itemId: entry.item.id, contentHash: entry.item.contentHash, decision: "done", target: nil, note: note)
        new.removeAll { $0.id == entry.id }
    }

    /// Move to top or bottom of the curated order; the list moves at once, the store confirms.
    func move(_ entry: TriageEntry, to edge: String) async throws {
        if let i = new.firstIndex(where: { $0.id == entry.id }) {
            let e = new.remove(at: i)
            if edge == "top" { new.insert(e, at: 0) } else { new.append(e) }
        }
        try await context?.move(itemId: entry.item.id, to: edge)
    }

    /// Drag: place the entry before or after a neighbour, in the list and in the store.
    func move(_ entry: TriageEntry, _ position: String, anchor: TriageEntry) async throws {
        if let i = new.firstIndex(where: { $0.id == entry.id }) {
            let e = new.remove(at: i)
            if let j = new.firstIndex(where: { $0.id == anchor.id }) {
                new.insert(e, at: position == "before" ? j : j + 1)
            } else {
                new.insert(e, at: i)
            }
        }
        try await context?.move(itemId: entry.item.id, to: position, anchor: anchor.item.id)
    }

    func ignore(_ entry: TriageEntry, note: String? = nil) async throws {
        try await context?.decide(itemId: entry.item.id, contentHash: entry.item.contentHash, decision: "ignore", target: nil, note: note)
        new.removeAll { $0.id == entry.id }
    }

    // MARK: Cards

    func detail(_ card: KanbanCard) async throws -> KanbanCardDetail {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        return try await auth.kanbanTask(card.id, board: card.board.isEmpty ? nil : card.board)
    }

    /// Proceed: the enriched card from the chat is written over the bare one and set ready, so the
    /// dispatcher picks it up. A card the chat named that does not exist yet is created.
    func proceed(_ proposed: ProposedCard, sessionId: String?) async throws -> KanbanCard {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        var body = proposed.body
        var links = proposed.links
        if let sid = sessionId, !links.contains(where: { $0.contains(sid) }) { links.append("talaria://chat/" + sid) }
        if let c = proposed.closes, !c.isEmpty { body += "\n\nCloses: " + c }
        if !links.isEmpty { body += "\n\nLinks:\n" + links.map { "- " + $0 }.joined(separator: "\n") }
        let boardName = (proposed.board.map { $0.isEmpty || $0 == "current" ? nil : $0 } ?? nil) ?? board
        let card: KanbanCard
        if let id = proposed.id, !id.isEmpty {
            try await auth.kanbanPatch(id, board: boardName, fields: ["title": proposed.title, "body": body, "assignee": proposed.assignee ?? ""])
            try await auth.kanbanPatch(id, board: boardName, fields: ["status": "ready"])
            card = try await auth.kanbanTask(id, board: boardName).card
        } else {
            let created = try await auth.kanbanCreate(board: boardName, title: proposed.title, body: body, assignee: proposed.assignee, triage: false, idempotencyKey: nil)
            card = created
        }
        if let sid = sessionId { rememberSession(sid, for: card.id) }
        await refresh()
        return card
    }

    /// Start now: a queued card jumps the line; a held card is released.
    func start(_ card: KanbanCard) async throws {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        let top = (backlog.map(\.priority).max() ?? 0) + 1
        try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["priority": top])
        if card.status != "ready" { try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["status": "ready"]) }
        await refresh()
    }

    /// Drop: archived; still on the board's archived column and in search.
    func drop(_ card: KanbanCard) async throws {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["status": "archived"])
        backlog.removeAll { $0.id == card.id }
    }

    /// Archive: a finished card leaves Done for the board's archived column, where it stays in
    /// search and in `list --archived`. The row goes at once; a failure puts it back on refresh.
    func archive(_ card: KanbanCard) async throws {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        done.removeAll { $0.id == card.id }
        do {
            try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["status": "archived"])
        } catch {
            await refresh()
            throw error
        }
    }

    /// Archive everything in Done. Stops at the first failure so the list shows what is left.
    func archiveDone() async throws {
        for card in done { try await archive(card) }
    }

    /// Answer a blocked card: the reply is a comment, then the card is released to run again.
    func reply(_ card: KanbanCard, _ text: String) async throws {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        try await auth.kanbanComment(card.id, board: card.board.isEmpty ? nil : card.board, text)
        if card.status == "blocked" { try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["status": "ready"]) }
        await refresh()
    }

    func stop(_ card: KanbanCard) async throws {
        guard let auth = settings.auth else { throw GatewayAuthError.notConfigured }
        try await auth.kanbanPatch(card.id, board: card.board.isEmpty ? nil : card.board, fields: ["status": "scheduled", "block_reason": "stopped from Talaria"])
        await refresh()
    }

    func rememberSession(_ sessionId: String, for cardId: String) {
        cardSessions[cardId] = sessionId
        UserDefaults.standard.set(cardSessions, forKey: Self.sessionMapKey)
    }

    // MARK: The first message of a Start or Why chat

    /// What the task-grill skill needs: the card and its links, as an attached file.
    static func startMessage(for card: KanbanCard, hasSkill: Bool) -> (text: String, file: (name: String, text: String)) {
        var doc = ["id: \(card.id)", "board: \(card.board.isEmpty ? "current" : card.board)", "title: \(card.title)"]
        if let a = card.assignee { doc.append("assignee: \(a)") }
        doc.append("status: \(card.status)")
        doc.append("")
        doc.append(card.body)
        let text = hasSkill ? "/task-grill" :
            "Enrich this task before it runs. Read the attached card and its source, look up what you can yourself, then ask me one question at a time until a worker could not go wrong; then post the finished task as a fenced `card` block (type: task, id, board, title, assignee, body, closes, links). Do not create or change the card yourself."
        return (text, ("task-\(card.id).md", doc.joined(separator: "\n")))
    }

    /// What the screener-feedback skill needs: the item, the screener's why and the decision.
    static func whyMessage(for entry: TriageEntry, decision: String, hasSkill: Bool) -> (text: String, file: (name: String, text: String)) {
        let item = entry.item
        var doc = ["item: \(item.id)", "source: \(item.sourceLine)", "title: \(item.title)", "decision: \(decision)"]
        if let u = item.url { doc.append("url: \(u)") }
        if let c = entry.candidate { doc.append("screener: \(c.why)") }
        doc.append("")
        doc.append(String(item.body.prefix(2000)))
        let text = hasSkill ? "/screener-feedback" :
            "I just decided \"\(decision)\" on the attached triage candidate. Check my past decisions for the same sender, chat or repo, ask one question that separates the rule from this instance, and propose a rule for the screener as a fenced `rule` block (scope, rule); on save append it to screener-rules.md in your home directory."
        return (text, ("triage-\(entry.item.id.hashValue).md", doc.joined(separator: "\n")))
    }
}
