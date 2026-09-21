import Foundation

// MARK: - Sessions (GET /api/sessions)

struct HermesSession: Codable, Identifiable, Hashable {
    let id: String
    var title: String?
    var source: String?
    var model: String?
    var startedAt: Double?
    var lastActive: Double?
    var messageCount: Int?
    var preview: String?
    var pinned: Bool?
    var archived: Bool?
    var parentSessionId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, source, model, preview, pinned, archived
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case parentSessionId = "parent_session_id"
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let p = preview, !p.isEmpty { return String(p.prefix(60)) }
        return "Untitled session"
    }

    var lastActiveDate: Date? {
        guard let ts = lastActive ?? startedAt else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

struct SessionPage: Codable {
    let data: [HermesSession]
    let hasMore: Bool?
    enum CodingKeys: String, CodingKey { case data; case hasMore = "has_more" }
}

// MARK: - Messages (GET /api/sessions/{id}/messages)

struct HermesToolCall: Codable, Hashable {
    struct Function: Codable, Hashable {
        let name: String?
        let arguments: String?
    }
    let id: String?
    let function: Function?
}

struct HermesMessage: Codable, Identifiable {
    let id: AnyID
    let role: String
    let content: AnyContent?
    let toolCallId: String?
    let toolCalls: [HermesToolCall]?
    let toolName: String?
    let timestamp: Double?
    let reasoning: String?
    let reasoningContent: String?
    let displayKind: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, reasoning
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
        case reasoningContent = "reasoning_content"
        case displayKind = "display_kind"
    }

    var text: String { content?.text ?? "" }
    var imageURLs: [String] { content?.imageURLs ?? [] }
    var reasoningText: String? {
        let r = reasoning ?? reasoningContent
        return (r?.isEmpty == false) ? r : nil
    }
}

struct MessagePage: Codable {
    let data: [HermesMessage]
}

/// Message ids may be ints or strings depending on the store.
struct AnyID: Codable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else if let s = try? c.decode(String.self) { value = s }
        else { value = UUID().uuidString }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// `content` is a string for most rows but can be a list of parts for multimodal turns.
struct AnyContent: Codable {
    let text: String
    /// Inline image data URLs found in typed content parts.
    let imageURLs: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s; imageURLs = []; return }
        if let parts = try? c.decode([[String: AnyJSON]].self) {
            text = parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            imageURLs = parts.compactMap { part in
                if case .object(let ref)? = part["image_url"] { return ref["url"]?.stringValue }
                return part["image_url"]?.stringValue
            }
            return
        }
        text = ""; imageURLs = []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

enum AnyJSON: Codable {
    case string(String), number(Double), bool(Bool), null
    case array([AnyJSON]), object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: AnyJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
}

// MARK: - Skills (GET /v1/skills)

struct Skill: Codable, Identifiable, Hashable {
    let name: String
    let description: String?
    let category: String?
    var id: String { name }
}

struct SkillPage: Codable {
    let data: [Skill]
}

// MARK: - Runs (POST /v1/runs, GET /v1/runs/{id}/events)

struct RunCreated: Codable {
    let runId: String
    let status: String?
    enum CodingKeys: String, CodingKey { case runId = "run_id"; case status }
}

/// One event off the run SSE stream. Payloads vary per event, so keep the raw dictionary.
struct RunEvent {
    let name: String
    let fields: [String: Any]

    init?(json: [String: Any]) {
        guard let name = json["event"] as? String else { return nil }
        self.name = name
        self.fields = json
    }

    func string(_ key: String) -> String? { fields[key] as? String }
    func double(_ key: String) -> Double? {
        if let d = fields[key] as? Double { return d }
        if let i = fields[key] as? Int { return Double(i) }
        return nil
    }
    func bool(_ key: String) -> Bool? { fields[key] as? Bool }
    func strings(_ key: String) -> [String]? { fields[key] as? [String] }
}

/// Pollable run state from `GET /v1/runs/{id}`.
struct RunStatus {
    let fields: [String: Any]
    var status: String { fields["status"] as? String ?? "" }
    var sessionId: String? { fields["session_id"] as? String }
    var output: String? { fields["output"] as? String }
    var error: String? { fields["error"] as? String }
    var approval: [String: Any]? { fields["approval"] as? [String: Any] }
    var isTerminal: Bool { ["completed", "failed", "cancelled", "interrupted"].contains(status) }
}

/// Approval prompt surfaced by an `approval.request` event or a parked run's status.
struct ApprovalRequest: Identifiable, Equatable {
    let id = UUID()
    let runId: String
    let requestId: String?
    let command: String
    let description: String
    let choices: [String]

    init(runId: String, fields: [String: Any]) {
        self.runId = runId
        self.requestId = fields["request_id"] as? String
        self.command = fields["command"] as? String ?? ""
        self.description = fields["description"] as? String ?? ""
        self.choices = fields["choices"] as? [String] ?? ["once", "deny"]
    }

    init(runId: String, event: RunEvent) { self.init(runId: runId, fields: event.fields) }

    static func == (a: ApprovalRequest, b: ApprovalRequest) -> Bool {
        a.runId == b.runId && a.requestId == b.requestId && a.command == b.command
    }
}
