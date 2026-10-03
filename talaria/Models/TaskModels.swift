import Foundation

/// One record in the context engine's store (mail, iMessage, meeting, issue, card…), as `/triage`
/// and `/item` return it. Fields follow the store's `events` row.
nonisolated struct ContextItem: Identifiable, Hashable, Sendable {
    let id: String
    let source: String
    let kind: String
    let title: String
    let body: String
    let url: String?
    let label: String?
    let owner: String?
    let participants: [String]
    let ts: Date
    let status: String?
    let contentHash: String?
    let attrs: [String: String]

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String else { return nil }
        self.id = id
        source = row["source"] as? String ?? ""
        kind = row["kind"] as? String ?? ""
        title = row["title"] as? String ?? ""
        body = row["body"] as? String ?? ""
        url = row["url"] as? String
        label = row["label"] as? String
        owner = row["owner"] as? String
        if let p = row["participants"] as? [String] { participants = p }
        else if let p = row["participants"] as? [[String: Any]] { participants = p.compactMap { $0["name"] as? String } }
        else { participants = [] }
        ts = Date(timeIntervalSince1970: (row["ts"] as? Double) ?? 0)
        status = row["status"] as? String
        contentHash = row["content_hash"] as? String
        var a: [String: String] = [:]
        for (k, v) in row["attrs"] as? [String: Any] ?? [:] { a[k] = "\(v)" }
        attrs = a
    }

    /// The source in words for a row's subtitle: "Mail · Namecheap", "iMessage · Summer", "talaria #12".
    var sourceLine: String {
        switch source {
        case "office365": return "Mail · " + (owner.flatMap { $0.isEmpty ? nil : $0 } ?? participants.first ?? "inbox")
        case "imessage": return "iMessage · " + (label ?? "")
        case "speakr": return "Meeting · " + (label ?? title)
        case "github": return (label ?? "GitHub") + (attrs["number"].map { " #\($0)" } ?? "")
        case "kanban": return "Card · " + (label ?? "default")
        case "reminders": return "Reminder · " + (label ?? "")
        case "manual": return "From Hermes"
        default: return source.capitalized
        }
    }

    /// SF Symbol for the source.
    var symbol: String {
        switch source {
        case "office365", "google": return "envelope"
        case "imessage": return "message"
        case "speakr": return "mic.fill"
        case "github": return "smallcircle.filled.circle"
        case "kanban": return "cpu"
        case "reminders": return "bell"
        case "obsidian": return "doc.text"
        case "manual": return "sparkles"
        default: return "tray"
        }
    }

    /// A hashtag naming the source, for the reminder's notes.
    var sourceTag: String {
        switch source {
        case "office365", "google": return "#mail"
        case "imessage": return "#imessage"
        case "speakr": return "#meeting"
        case "github": return "#github"
        case "kanban", "manual": return "#hermes"
        default: return "#" + source
        }
    }
}

/// What the screener said about an item.
nonisolated struct TriageCandidate: Hashable, Sendable {
    let title: String
    let why: String
    let suggested: String?
    let suggestedDue: Date?
    let createdAt: Date

    init(row: [String: Any]) {
        title = row["title"] as? String ?? ""
        why = row["why"] as? String ?? ""
        suggested = row["suggested"] as? String
        suggestedDue = (row["suggested_due"] as? String).flatMap { s in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            return f.date(from: String(s.prefix(10)))
        }
        createdAt = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? 0)
    }
}

/// A row in the Triage list's New section.
nonisolated struct TriageEntry: Identifiable, Hashable, Sendable {
    let item: ContextItem
    let candidate: TriageCandidate?
    var id: String { item.id }
    var title: String { candidate?.title.isEmpty == false ? candidate!.title : item.title }
}

/// A kanban card as the dashboard plugin reports it (`/board` and `/tasks/{id}`).
nonisolated struct KanbanCard: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let status: String
    let assignee: String?
    let priority: Int
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let sessionId: String?
    let idempotencyKey: String?
    let blockKind: String?
    let latestSummary: String?
    let lastError: String?
    let branch: String?
    let workspace: String?
    let parentCount: Int
    let board: String

    init?(row: [String: Any], board: String = "default") {
        guard let id = row["id"] as? String else { return nil }
        self.id = id
        title = row["title"] as? String ?? ""
        body = row["body"] as? String ?? ""
        status = row["status"] as? String ?? "triage"
        assignee = (row["assignee"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        priority = row["priority"] as? Int ?? 0
        createdAt = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? 0)
        startedAt = (row["started_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        completedAt = (row["completed_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        sessionId = row["session_id"] as? String
        idempotencyKey = row["idempotency_key"] as? String
        blockKind = row["block_kind"] as? String
        latestSummary = row["latest_summary"] as? String ?? row["result"] as? String
        lastError = row["last_failure_error"] as? String
        branch = row["branch_name"] as? String
        workspace = row["workspace_path"] as? String
        parentCount = (row["link_counts"] as? [String: Any])?["parents"] as? Int ?? 0
        self.board = board
    }

    var isBacklog: Bool { ["triage", "todo", "scheduled"].contains(status) }
    var isInProgress: Bool { ["running", "blocked", "review", "ready"].contains(status) }
    var needsYou: Bool { status == "blocked" && (blockKind == nil || blockKind == "needs_input" || blockKind == "capability") }

    /// The `#tags` in title and body.
    var tags: [String] {
        var out: [String] = []
        let text = title + " " + body
        var i = text.startIndex
        while let hash = text[i...].firstIndex(of: "#") {
            let before = hash > text.startIndex ? text[text.index(before: hash)] : " "
            var end = text.index(after: hash)
            while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "-" { end = text.index(after: end) }
            let word = String(text[text.index(after: hash)..<end]).lowercased()
            if before.isWhitespace || before == "(", word.count > 1, word.first!.isLetter, !out.contains(word) { out.append(word) }
            i = end
        }
        return out
    }

    /// A link back to the source when the body carries one.
    var sourceURL: URL? {
        for line in body.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["source:", "- https://", "https://github.com/"] where s.hasPrefix(prefix) {
                let raw = s.hasPrefix("source:") ? String(s.dropFirst(7)) : (s.hasPrefix("- ") ? String(s.dropFirst(2)) : s)
                if let u = URL(string: raw.trimmingCharacters(in: .whitespaces)) { return u }
            }
        }
        return nil
    }
}

nonisolated struct KanbanComment: Identifiable, Hashable, Sendable {
    let id: Int
    let author: String
    let body: String
    let createdAt: Date
    init?(row: [String: Any]) {
        guard let id = row["id"] as? Int else { return nil }
        self.id = id
        author = row["author"] as? String ?? ""
        body = row["body"] as? String ?? ""
        createdAt = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? 0)
    }
}

nonisolated struct KanbanEvent: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: String
    let summary: String
    let createdAt: Date
    init?(row: [String: Any]) {
        guard let id = row["id"] as? Int else { return nil }
        self.id = id
        kind = row["kind"] as? String ?? ""
        let p = row["payload"] as? [String: Any] ?? [:]
        var bits: [String] = []
        for key in ["profile", "assignee", "reason", "summary", "status", "error", "question"] {
            if let v = p[key] as? String, !v.isEmpty { bits.append(v) }
        }
        summary = bits.joined(separator: " · ")
        createdAt = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? 0)
    }
}

/// A card's full record: the card, its comments and its events.
nonisolated struct KanbanCardDetail: Sendable {
    let card: KanbanCard
    let comments: [KanbanComment]
    let events: [KanbanEvent]
}

/// A `card` block Hermes wrote in a reply: something that may not exist yet (a task to file, a
/// reminder to add) or a reference to one that does.
nonisolated struct ProposedCard: Hashable, Sendable {
    enum Kind: String, Sendable { case task, reminder, issue }
    var kind: Kind = .task
    var id: String?
    var board: String?
    var title = ""
    var assignee: String?
    var body = ""
    var closes: String?
    var links: [String] = []
    var due: Date?
    var time: String?
    var list: String?
    var url: String?
    var tags: [String] = []
    /// Keys that were present but not understood, kept so nothing is silently dropped.
    var extra: [String: String] = [:]

    /// Parses the small YAML subset the skills write: `key: value`, `key: |` with an indented
    /// block, and `key:` followed by `- item` lines.
    init(yaml: String) {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        func indentOf(_ s: String) -> Int { s.prefix { $0 == " " }.count }
        while i < lines.count {
            let line = lines[i]
            i += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if let hash = value.range(of: "   #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
            if value == "|" || value == ">" {
                var block: [String] = []
                var base: Int?
                while i < lines.count {
                    let l = lines[i]
                    if !l.trimmingCharacters(in: .whitespaces).isEmpty && indentOf(l) == 0 { break }
                    if base == nil, !l.trimmingCharacters(in: .whitespaces).isEmpty { base = indentOf(l) }
                    block.append(String(l.dropFirst(min(base ?? 0, indentOf(l)))))
                    i += 1
                }
                while block.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { block.removeLast() }
                value = block.joined(separator: "\n")
            } else if value.isEmpty {
                var items: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    items.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                value = items.joined(separator: "\n")
            } else if value.hasPrefix("[") && value.hasSuffix("]") {
                value = value.dropFirst().dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            }
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            switch key {
            case "type": kind = Kind(rawValue: value) ?? .task
            case "id": id = value.isEmpty ? nil : value
            case "board": board = value
            case "title": title = value
            case "assignee": assignee = value.isEmpty ? nil : value
            case "body", "notes": body = value
            case "closes": closes = value
            case "links": links = value.split(separator: "\n").map(String.init)
            case "due":
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
                due = f.date(from: String(value.prefix(10)))
            case "time": time = value
            case "list": list = value
            case "url": url = value
            case "tags": tags = value.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            default: extra[key] = value
            }
        }
    }
}
