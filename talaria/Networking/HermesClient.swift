import Foundation

enum HermesError: LocalizedError {
    case badURL
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decode(let what): return "Could not decode \(what)"
        }
    }
}

/// Thin client over the Hermes API server: Sessions API for history, Runs API for streaming turns,
/// `/v1/skills` for discovery. All calls send `Authorization: Bearer <API_SERVER_KEY>`.
struct HermesClient {
    let baseURL: URL
    let apiKey: String

    private var session: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: cfg)
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Any? = nil) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw HermesError.badURL
        }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw HermesError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func data(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw HermesError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw HermesError.decode("\(type): \(error)") }
    }

    // MARK: Health

    func health() async throws -> Bool {
        let d = try await data(try request("GET", "/health"))
        let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        return (obj?["status"] as? String) == "ok"
    }

    // MARK: Sessions

    func listSessions(limit: Int = 50, offset: Int = 0) async throws -> SessionPage {
        try decode(SessionPage.self, try await data(try request("GET", "/api/sessions", query: ["limit": "\(limit)", "offset": "\(offset)"])))
    }

    func createSession(title: String? = nil) async throws -> HermesSession {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        let d = try await data(try request("POST", "/api/sessions", body: body))
        // Tolerate either a bare session object or one wrapped in `data`/`session`.
        if let s = try? JSONDecoder().decode(HermesSession.self, from: d) { return s }
        if let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for key in ["data", "session"] {
                if let inner = obj[key], let inner = try? JSONSerialization.data(withJSONObject: inner),
                   let s = try? JSONDecoder().decode(HermesSession.self, from: inner) { return s }
            }
            if let id = obj["id"] as? String ?? obj["session_id"] as? String {
                return HermesSession(id: id, title: title)
            }
        }
        throw HermesError.decode("session")
    }

    func getSession(id: String) async throws -> HermesSession {
        try decode(HermesSession.self, try await data(try request("GET", "/api/sessions/\(id)")))
    }

    func updateSession(id: String, fields: [String: Any]) async throws {
        _ = try await data(try request("PATCH", "/api/sessions/\(id)", body: fields))
    }

    func deleteSession(id: String) async throws {
        _ = try await data(try request("DELETE", "/api/sessions/\(id)"))
    }

    func messages(sessionId: String) async throws -> [HermesMessage] {
        try decode(MessagePage.self, try await data(try request("GET", "/api/sessions/\(sessionId)/messages", query: ["order": "oldest", "limit": "500"]))).data
    }

    // MARK: Skills

    func skills() async throws -> [Skill] {
        try decode(SkillPage.self, try await data(try request("GET", "/v1/skills"))).data
    }

    // MARK: Runs

    /// Text-only turns send `input` as a string; turns with images send one OpenAI-style user
    /// message whose content mixes `text` and `image_url` parts (data URLs).
    ///
    /// `history` is the prior user/assistant turns. The gateway version on the server may not load
    /// a session's transcript for `/v1/runs` on its own, so the client always supplies it; the turn
    /// is still persisted to the session either way.
    func createRun(input: String, imageDataURLs: [String] = [], history: [[String: String]] = [], sessionId: String) async throws -> String {
        var body: [String: Any] = ["session_id": sessionId]
        if !history.isEmpty { body["conversation_history"] = history }
        if imageDataURLs.isEmpty {
            body["input"] = input
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": input]]
            parts += imageDataURLs.map { ["type": "image_url", "image_url": ["url": $0]] }
            body["input"] = [["role": "user", "content": parts]]
        }
        var req = try request("POST", "/v1/runs", body: body)
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        return try decode(RunCreated.self, try await data(req)).runId
    }

    func runStatus(id: String) async throws -> RunStatus {
        let d = try await data(try request("GET", "/v1/runs/\(id)"))
        guard let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw HermesError.decode("run status") }
        return RunStatus(fields: obj)
    }

    func steer(runId: String, text: String) async throws {
        _ = try await data(try request("POST", "/v1/runs/\(runId)/steer", body: ["input": text]))
    }

    func stopRun(id: String) async throws {
        _ = try await data(try request("POST", "/v1/runs/\(id)/stop", body: [:]))
    }

    func approve(runId: String, choice: String, requestId: String?) async throws {
        var body: [String: Any] = ["choice": choice]
        if let requestId { body["request_id"] = requestId }
        _ = try await data(try request("POST", "/v1/runs/\(runId)/approval", body: body))
    }

    /// Streams `GET /v1/runs/{id}/events`. Each SSE frame's `data` is a JSON object with an `event` name.
    func events(runId: String) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try request("GET", "/v1/runs/\(runId)/events")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await session.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard code == 200 else { throw HermesError.http(code, "event stream refused") }
                    // `bytes.lines` drops empty lines, which are the SSE frame terminators, so split by hand.
                    var parser = SSEParser()
                    var buffer: [UInt8] = []
                    func handle(_ raw: [UInt8]) {
                        var line = String(decoding: raw, as: UTF8.self)
                        if line.hasSuffix("\r") { line.removeLast() }
                        guard let frame = parser.feed(line: line) else { return }
                        guard let obj = try? JSONSerialization.jsonObject(with: Data(frame.data.utf8)) as? [String: Any],
                              let event = RunEvent(json: obj) else { return }
                        continuation.yield(event)
                    }
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            handle(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty { handle(buffer) }
                    handle([]) // flush a final frame that had no trailing blank line
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
