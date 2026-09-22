import Foundation

/// A stored session as `session.list` reports it, plus the live id once resumed.
struct HermesSession: Identifiable, Hashable {
    /// Stored (database) id; what the sidebar and pins key on.
    let id: String
    /// Live id used on events and RPC once the session is resumed or created.
    var liveId: String
    var title: String?
    var preview: String?
    var startedAt: Double?
    var messageCount: Int?
    var source: String?

    init(id: String, liveId: String? = nil, title: String? = nil, preview: String? = nil,
         startedAt: Double? = nil, messageCount: Int? = nil, source: String? = nil) {
        self.id = id; self.liveId = liveId ?? id; self.title = title; self.preview = preview
        self.startedAt = startedAt; self.messageCount = messageCount; self.source = source
    }

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String else { return nil }
        self.init(id: id, liveId: row["resolved_id"] as? String ?? id, title: row["title"] as? String,
                  preview: row["preview"] as? String, startedAt: row["started_at"] as? Double,
                  messageCount: row["message_count"] as? Int, source: row["source"] as? String)
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let p = preview, !p.isEmpty { return String(p.prefix(60)) }
        return "Untitled session"
    }

    var startedDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0) } }
}

/// One durable transcript row from `session.history` / `session.resume`.
struct TranscriptMessage {
    let role: String
    let text: String
    let displayKind: String?
    let name: String?
    let args: [String: Any]?
    let reasoning: String?
    let rowId: Int?

    init?(row: [String: Any]) {
        guard let role = row["role"] as? String else { return nil }
        self.role = role
        text = row["text"] as? String ?? ""
        displayKind = row["display_kind"] as? String
        name = row["name"] as? String
        args = row["args"] as? [String: Any]
        reasoning = row["reasoning"] as? String
        rowId = row["row_id"] as? Int
    }
}

struct Skill: Identifiable, Hashable {
    let name: String
    var description: String?
    var category: String?
    var id: String { name }
}

/// A dangerous-command approval waiting on the person. Answered through the gateway request.
struct ApprovalRequest: Identifiable, Equatable {
    let id: String
    let sessionId: String?
    let command: String
    let description: String
    let choices: [String]
    let toolName: String?
    let request: ServerRequest?

    init(request: ServerRequest) {
        id = request.id
        sessionId = request.sessionId
        command = request.string("command") ?? ""
        description = request.string("description") ?? ""
        choices = request.params["choices"] as? [String] ?? ["once", "deny"]
        toolName = request.string("tool_name")
        self.request = request
    }

    static func == (a: ApprovalRequest, b: ApprovalRequest) -> Bool { a.id == b.id }
}

/// The clarify tool asking one question with optional choices.
struct ClarifyRequest: Identifiable, Equatable {
    let id: String
    let sessionId: String?
    let question: String
    let choices: [String]
    let request: ServerRequest

    init(request: ServerRequest) {
        id = request.id
        sessionId = request.sessionId
        var q = request.string("question") ?? ""
        var c = request.params["choices"] as? [String] ?? []
        if q.isEmpty, let batch = request.params["questions"] as? [[String: Any]], let first = batch.first {
            q = first["question"] as? String ?? ""
            c = first["choices"] as? [String] ?? []
        }
        question = q
        choices = c
        self.request = request
    }

    static func == (a: ClarifyRequest, b: ClarifyRequest) -> Bool { a.id == b.id }
}
