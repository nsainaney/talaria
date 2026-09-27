import Foundation

/// The hermes-context engine as the dashboard's `talaria` plugin exposes it
/// (`/api/plugins/talaria/…`): the triage list, decisions, scans, items and a server-sent event
/// stream. Same cookie session as the dashboard, one silent re-login on 401.
struct ContextClient {
    let auth: GatewayAuth

    enum Error: LocalizedError {
        case http(Int, String)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Context engine returned HTTP \(code): \(body)"
            case .badResponse: return "Context engine returned an unexpected response"
            }
        }
    }

    struct Scanning: Sendable, Equatable {
        let id: String
        let total: Int
        let done: Int
        let found: Int
        let skipped: Int
        let skippedReason: String?
        /// Per source: total, done, found, skipped (deferred by the budget). A source with nothing to do has total 0.
        let bySource: [(source: String, total: Int, done: Int, found: Int, skipped: Int)]

        init(id: String, total: Int, done: Int, found: Int, skipped: Int, skippedReason: String?,
             bySource: [(source: String, total: Int, done: Int, found: Int, skipped: Int)] = []) {
            self.id = id; self.total = total; self.done = done; self.found = found; self.skipped = skipped; self.skippedReason = skippedReason
            self.bySource = bySource
        }

        init?(row: [String: Any]) {
            guard let id = row["id"] as? String else { return nil }
            let by = (row["by_source"] as? [String: [String: Any]] ?? [:]).map { k, v in
                (source: k, total: v["total"] as? Int ?? 0, done: v["done"] as? Int ?? 0, found: v["found"] as? Int ?? 0, skipped: v["skipped"] as? Int ?? 0)
            }.sorted { $0.source < $1.source }
            self.init(id: id, total: row["total"] as? Int ?? 0, done: row["done"] as? Int ?? 0, found: row["found"] as? Int ?? 0,
                      skipped: row["skipped"] as? Int ?? 0, skippedReason: row["skip_reason"] as? String ?? row["skipped_reason"] as? String, bySource: by)
        }

        static func == (a: Scanning, b: Scanning) -> Bool {
            a.id == b.id && a.total == b.total && a.done == b.done && a.found == b.found && a.skipped == b.skipped
        }
    }

    struct Triage: Sendable {
        let asOf: Date
        let scanning: Scanning?
        let new: [TriageEntry]
        let backlog: [ContextItem]
    }

    private static let root = "/api/plugins/talaria"

    private var session: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        var comps = URLComponents(url: auth.baseURL.appendingPathComponent(Self.root + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func json(_ req: URLRequest) async throws -> [String: Any] {
        if let obj = try await once(req) { return obj }
        try await auth.login()
        guard let obj = try await once(req) else { throw GatewayAuthError.badCredentials }
        return obj
    }

    private func once(_ req: URLRequest) async throws -> [String: Any]? {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Error.badResponse }
        if http.statusCode == 401 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw Error.http(http.statusCode, detail ?? String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Error.badResponse }
        return obj
    }

    /// The triage list: candidates without a decision, plus the kanban backlog as the store mirrors it.
    func triage() async throws -> Triage {
        let obj = try await json(request("GET", "/triage"))
        let new: [TriageEntry] = (obj["new"] as? [[String: Any]] ?? []).compactMap { row in
            guard let itemRow = row["item"] as? [String: Any], let item = ContextItem(row: itemRow) else { return nil }
            return TriageEntry(item: item, candidate: (row["candidate"] as? [String: Any]).map(TriageCandidate.init(row:)))
        }
        let backlog = (obj["backlog"] as? [[String: Any]] ?? []).compactMap(ContextItem.init(row:))
        return Triage(asOf: Date(timeIntervalSince1970: (obj["as_of"] as? Double) ?? Date().timeIntervalSince1970),
                      scanning: (obj["scanning"] as? [String: Any]).flatMap(Scanning.init(row:)), new: new, backlog: backlog)
    }

    /// Records what the user did with an item. `target` is "reminder:<id>" or "card:<board>:<id>".
    func decide(itemId: String, contentHash: String?, decision: String, target: String?, note: String? = nil, sessionId: String? = nil) async throws {
        var body: [String: Any] = ["item_id": itemId, "decision": decision]
        if let contentHash { body["content_hash"] = contentHash }
        if let target { body["target"] = target }
        if let note, !note.isEmpty { body["note"] = note }
        if let sessionId { body["session_id"] = sessionId }
        _ = try await json(request("POST", "/decisions", body: body))
    }

    /// Starts a scan, or returns the one already running.
    func scan() async throws -> String {
        let obj = try await json(request("POST", "/scan", body: [:]))
        guard let id = obj["id"] as? String else { throw Error.badResponse }
        return id
    }

    /// Moves a candidate in the curated order. New items append at the bottom; nothing else reorders.
    func move(itemId: String, to: String, anchor: String? = nil) async throws {
        var body: [String: Any] = ["action": "move", "item_id": itemId, "to": to]
        if let anchor { body["anchor"] = anchor }
        _ = try await json(request("POST", "/tasks", body: body))
    }

    func item(_ id: String) async throws -> ContextItem? {
        let obj = try await json(request("GET", "/item/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)))
        return (obj["item"] as? [String: Any]).flatMap(ContextItem.init(row:))
    }

    /// One event from `/stream`: `{"topic": "hermes/triage/decision", "data": {...}}`.
    struct Event: Sendable {
        let topic: String
        let data: [String: Any]
    }

    /// The server-sent event stream. Ends when the connection drops; the caller reconnects.
    func stream() throws -> AsyncThrowingStream<Event, Swift.Error> {
        var req = try request("GET", "/stream")
        req.timeoutInterval = 3600
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return Self.events(session: session, request: req)
    }

    nonisolated private static func events(session: URLSession, request: URLRequest) -> AsyncThrowingStream<Event, Swift.Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let (bytes, resp) = try await session.bytes(for: request)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw Error.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "stream")
                    }
                    // `bytes.lines` drops the blank line that ends an event, so split by hand.
                    var buffer = Data()
                    var dataLines: [String] = []
                    for try await byte in bytes {
                        if byte != UInt8(ascii: "\n") { buffer.append(byte); continue }
                        let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                        buffer.removeAll(keepingCapacity: true)
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let payload = dataLines.joined(separator: "\n")
                                dataLines.removeAll()
                                if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] {
                                    continuation.yield(Event(topic: obj["topic"] as? String ?? "", data: obj["data"] as? [String: Any] ?? obj))
                                }
                            }
                            continue
                        }
                        if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
