import Foundation

/// The dashboard's kanban plugin (`/api/plugins/kanban/…`). Same cookie session as the rest of the
/// dashboard, with one silent re-login on 401.
extension GatewayAuth {
    private var kanbanSession: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    private func kanbanRequest(_ method: String, _ path: String, board: String?, body: [String: Any]? = nil) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/plugins/kanban" + path), resolvingAgainstBaseURL: false)!
        if let board, !board.isEmpty { comps.queryItems = [URLQueryItem(name: "board", value: board)] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func kanban(_ method: String, _ path: String, board: String?, body: [String: Any]? = nil) async throws -> [String: Any] {
        if let obj = try await kanbanOnce(method, path, board: board, body: body) { return obj }
        try await login()
        guard let obj = try await kanbanOnce(method, path, board: board, body: body) else { throw GatewayAuthError.badCredentials }
        return obj
    }

    private func kanbanOnce(_ method: String, _ path: String, board: String?, body: [String: Any]?) async throws -> [String: Any]? {
        let (data, resp) = try await kanbanSession.data(for: kanbanRequest(method, path, board: board, body: body))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { return nil }
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"]
            throw GatewayAuthError.http(code, (detail as? String) ?? String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Every card on the board, grouped by status column.
    func kanbanBoard(_ board: String?) async throws -> [String: [KanbanCard]] {
        let obj = try await kanban("GET", "/board", board: board)
        // No board setting means the dashboard's current board; keep that empty so later calls
        // also omit the parameter, rather than naming the separate "default" board.
        let name = obj["board"] as? String ?? board ?? ""
        var out: [String: [KanbanCard]] = [:]
        // `columns` is a list of {name, tasks}; older builds used a dict keyed by status.
        if let list = obj["columns"] as? [[String: Any]] {
            for col in list {
                guard let column = col["name"] as? String else { continue }
                out[column] = (col["tasks"] as? [[String: Any]] ?? []).compactMap { KanbanCard(row: $0, board: name) }
            }
        } else if let dict = obj["columns"] as? [String: [[String: Any]]] {
            for (column, rows) in dict { out[column] = rows.compactMap { KanbanCard(row: $0, board: name) } }
        }
        return out
    }

    func kanbanTask(_ id: String, board: String?) async throws -> KanbanCardDetail {
        let obj = try await kanban("GET", "/tasks/\(id)", board: board)
        guard let row = obj["task"] as? [String: Any] ?? (obj["id"] != nil ? obj : nil),
              let card = KanbanCard(row: row, board: board ?? "") else { throw GatewayAuthError.http(0, "no task in response") }
        let comments = (obj["comments"] as? [[String: Any]] ?? []).compactMap(KanbanComment.init(row:))
        let events = (obj["events"] as? [[String: Any]] ?? []).compactMap(KanbanEvent.init(row:))
        return KanbanCardDetail(card: card, comments: comments, events: events)
    }

    /// Creates a card. `triage` keeps it out of the dispatcher's reach until Proceed sets it ready,
    /// provided the server has `kanban.auto_decompose` off: by default the gateway rewrites and
    /// starts triage cards itself.
    func kanbanCreate(board: String?, title: String, body: String, assignee: String?, triage: Bool, idempotencyKey: String?) async throws -> KanbanCard {
        var payload: [String: Any] = ["title": title, "body": body, "triage": triage]
        if let assignee { payload["assignee"] = assignee }
        if let idempotencyKey { payload["idempotency_key"] = idempotencyKey }
        let obj = try await kanban("POST", "/tasks", board: board, body: payload)
        guard let row = obj["task"] as? [String: Any], let card = KanbanCard(row: row, board: board ?? "") else {
            throw GatewayAuthError.http(0, "no task in response")
        }
        return card
    }

    /// Any of title, body, assignee, status, priority. Status changes go through the board's own
    /// transition rules; a refused one comes back as HTTP 409 with the reason.
    /// Returns the card as the board has it after the change.
    @discardableResult
    func kanbanPatch(_ id: String, board: String?, fields: [String: Any]) async throws -> KanbanCard? {
        let obj = try await kanban("PATCH", "/tasks/\(id)", board: board, body: fields)
        return (obj["task"] as? [String: Any]).flatMap { KanbanCard(row: $0, board: board ?? "") }
    }

    /// Ends a running card's worker and releases its claim. False when there was nothing to
    /// reclaim, which the board answers with 409.
    @discardableResult
    func kanbanReclaim(_ id: String, board: String?, reason: String) async throws -> Bool {
        do {
            _ = try await kanban("POST", "/tasks/\(id)/reclaim", board: board, body: ["reason": reason])
            return true
        } catch GatewayAuthError.http(409, _) {
            return false
        }
    }

    func kanbanComment(_ id: String, board: String?, _ text: String) async throws {
        _ = try await kanban("POST", "/tasks/\(id)/comments", board: board, body: ["body": text, "author": username.isEmpty ? "talaria" : username])
    }

    func kanbanDelete(_ id: String, board: String?) async throws {
        _ = try await kanban("DELETE", "/tasks/\(id)", board: board)
    }

    /// Profiles the dispatcher can spawn, for the Agent picker.
    func kanbanAssignees(_ board: String?) async throws -> [String] {
        let obj = try await kanban("GET", "/assignees", board: board)
        if let rows = obj["assignees"] as? [[String: Any]] { return rows.filter { ($0["on_disk"] as? Bool) ?? true }.compactMap { $0["name"] as? String } }
        if let names = obj["assignees"] as? [String] { return names }
        if let rows = obj["profiles"] as? [[String: Any]] { return rows.compactMap { $0["name"] as? String } }
        return []
    }
}
