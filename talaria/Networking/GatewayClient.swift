import Foundation
import os
import Observation

/// One event frame from the gateway (`{"method":"event","params":{type, session_id, seq, payload}}`).
struct GatewayEvent {
    let type: String
    let sessionId: String?
    let seq: Int?
    let payload: [String: Any]
    let replayed: Bool

    init?(params: [String: Any], replayed: Bool = false) {
        guard let type = params["type"] as? String else { return nil }
        self.type = type
        sessionId = params["session_id"] as? String
        seq = params["seq"] as? Int
        payload = params["payload"] as? [String: Any] ?? [:]
        self.replayed = replayed
    }

    func string(_ key: String) -> String? { payload[key] as? String }
    func bool(_ key: String) -> Bool? { payload[key] as? Bool }
    func double(_ key: String) -> Double? {
        if let d = payload[key] as? Double { return d }
        if let i = payload[key] as? Int { return Double(i) }
        return nil
    }
}

/// A server-to-client request (approval, clarify, …). Exactly one of `respond`/`fail` must be called.
final class ServerRequest {
    let id: String
    let method: String
    let params: [String: Any]
    let replayed: Bool
    private let reply: ([String: Any]?, (Int, String)?) -> Bool
    private var settled = false

    init(id: String, method: String, params: [String: Any], replayed: Bool, reply: @escaping ([String: Any]?, (Int, String)?) -> Bool) {
        self.id = id; self.method = method; self.params = params; self.replayed = replayed; self.reply = reply
    }

    var sessionId: String? { params["session_id"] as? String }
    func string(_ key: String) -> String? { params[key] as? String }

    /// False when there was no socket to send on; the request is still open and can be answered again.
    @discardableResult
    func respond(_ result: [String: Any]) -> Bool { guard !settled else { return true }; settled = reply(result, nil); return settled }
    @discardableResult
    func fail(code: Int, message: String) -> Bool { guard !settled else { return true }; settled = reply(nil, (code, message)); return settled }
}

enum GatewayError: LocalizedError {
    case notConnected
    case rpc(code: Int?, message: String)
    case timeout(String)
    case badFrame

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Hermes."
        case .rpc(let code, let message): return code.map { "\(message) (\($0))" } ?? message
        case .timeout(let m): return "Timed out: \(m)"
        case .badFrame: return "Unexpected reply from Hermes."
        }
    }

    /// The gateway no longer has the live session (reaped while idle); the stored one can be resumed.
    var isSessionGone: Bool {
        if case .rpc(let code, let message) = self { return code == 4001 && message.localizedCaseInsensitiveContains("session not found") }
        return false
    }
}

/// JSON-RPC 2.0 client for the Hermes `tui_gateway` protocol over the dashboard WebSocket.
/// Keeps per-session event sequence watermarks and replays gaps after a reconnect.
@Observable @MainActor
final class GatewayClient {
    enum State: Equatable {
        case disconnected, connecting, connected
        case reconnecting(attempt: Int)
        case failed(String)
    }

    var state: State = .disconnected {
        didSet { if state != oldValue { Self.log.notice("gateway \(String(describing: self.state), privacy: .public)") } }
    }
    var isConnected: Bool { state == .connected }
    private static let log = Logger(subsystem: "com.sainaney.talaria", category: "gateway")

    /// Dispatched on the main actor, in order, seq-gated per session.
    var onEvent: ((GatewayEvent) -> Void)?
    /// Return false when the request kind is not handled; it is then failed as method-not-found.
    var onServerRequest: ((ServerRequest) -> Bool)?
    /// A session's replay was truncated or the server restarted: reload that session's state.
    var onResync: ((String) -> Void)?
    /// The socket is up and caught up, on the first connection and after every reconnect.
    var onConnected: (() -> Void)?
    /// After a replay: the ids of the server requests still open for a session.
    var onOpenRequests: ((String, Set<String>) -> Void)?
    /// The gateway process restarted; whatever it was waiting on is gone.
    var onServerRestart: (() -> Void)?

    private var auth: GatewayAuth?
    private var socket: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    /// Which run loop owns the connection; a superseded loop sees a newer id and leaves.
    private var loopId = 0
    /// The current backoff wait, a task of its own so `wake()` can cut it short.
    private var backoff: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var generation = 0
    private var nextId = 0
    private var pending: [String: CheckedContinuation<Any?, Error>] = [:]
    private var lastSeenSeq: [String: Int] = [:]
    private var replayEpoch: String?
    private var replayHold: [String: [GatewayEvent]]?
    private var wantConnected = false
    /// The server tells "not shown on this client" (4404) from a refusal; newer than Hermes 0.21.
    private var declinesNotShown = false

    private let urlSession = URLSession(configuration: .default)

    // MARK: Connection lifecycle

    /// Idempotent: reconnects only when the credentials or server changed. After a sign-in
    /// failure stopped the loop, calling it again makes one more attempt.
    func connect(auth: GatewayAuth) {
        let changed = self.auth.map { $0.baseURL != auth.baseURL || $0.username != auth.username || $0.password != auth.password } ?? true
        self.auth = auth
        wantConnected = true
        if changed, runTask != nil {
            runTask?.cancel()
            runTask = nil
            backoff?.cancel()
            closeSocket(reason: GatewayError.notConnected)
        }
        guard runTask == nil else { return }
        loopId += 1
        let id = loopId
        runTask = Task { [weak self] in await self?.runLoop(id) }
    }

    func disconnect() {
        wantConnected = false
        runTask?.cancel()
        runTask = nil
        backoff?.cancel()
        closeSocket(reason: GatewayError.notConnected)
        state = .disconnected
        lastSeenSeq = [:]
        replayEpoch = nil
    }

    /// The app is in the foreground again. A backoff wait is cut short, and a socket that sat
    /// through a suspension is proven with a quick ping rather than trusted. True when a live
    /// socket answered.
    func wake() async -> Bool {
        guard wantConnected else { return false }
        backoff?.cancel()
        guard socket != nil, state == .connected else { return false }
        let gen = generation
        do {
            _ = try await request("ping", timeout: 5)
            return true
        } catch {
            if gen == generation { closeSocket(reason: GatewayError.timeout("wake")) }
            return false
        }
    }

    /// Forget a session's watermark (after delete or when it is no longer shown).
    func forgetSession(_ id: String) { lastSeenSeq[id] = nil }

    private func owns(_ id: Int) -> Bool { id == loopId && wantConnected && !Task.isCancelled }

    private func runLoop(_ id: Int) async {
        var attempt = 0
        while owns(id) {
            state = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
            var wait: Double?
            do {
                guard let auth else { throw GatewayAuthError.notConfigured }
                let ticket = try await auth.wsTicket()
                guard owns(id) else { break }
                let closed = try await open(url: auth.webSocketURL(ticket: ticket))
                guard owns(id) else { break }
                attempt = 0
                state = .connected
                await replayAfterReconnect()
                if owns(id) { onConnected?() }
                await closed.value   // runs until the socket drops
                guard owns(id) else { break }
                state = .reconnecting(attempt: 1)
            } catch {
                guard owns(id) else { break }
                state = .failed(error.localizedDescription)
                if let e = error as? GatewayAuthError {
                    // Asking again cannot fix these and the sign-in endpoint is throttled, so stop
                    // here; the banner keeps the reason until the person signs in again.
                    if e.needsSignIn { break }
                    if case .rateLimited = e { wait = 90 }
                    attempt = max(attempt, 3) // slow down on auth trouble
                }
            }
            attempt += 1
            await pause(wait ?? min(30.0, pow(2.0, Double(attempt - 1))) + Double.random(in: 0...0.5))
        }
        if id == loopId {
            runTask = nil
            if !wantConnected { state = .disconnected }
        }
    }

    /// The wait between attempts; ends early when `wake()` or a new `connect` cancels it.
    private func pause(_ seconds: Double) async {
        let sleep = Task<Void, Never> { do { try await Task.sleep(for: .seconds(seconds)) } catch {} }
        backoff = sleep
        await withTaskCancellationHandler { await sleep.value } onCancel: { sleep.cancel() }
    }

    /// Opens the socket and proves it with a `ping`; returns a task that completes when the socket closes.
    private func open(url: URL) async throws -> Task<Void, Never> {
        generation += 1
        let gen = generation
        let task = urlSession.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
        socket = task
        task.resume()
        let closed = Task<Void, Never> { [weak self] in await self?.receiveLoop(task: task, gen: gen) ?? () }
        do {
            _ = try await request("ping", timeout: 45)
        } catch {
            closed.cancel()
            if gen == generation { closeSocket(reason: error) } else { task.cancel(with: .goingAway, reason: nil) }
            throw error
        }
        startHeartbeat(gen: gen)
        return closed
    }

    private func receiveLoop(task: URLSessionWebSocketTask, gen: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard gen == generation else { return }
                switch message {
                case .string(let text): handle(text: text)
                case .data(let data): handle(text: String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                if gen == generation { closeSocket(reason: error) }
                return
            }
        }
    }

    private func closeSocket(reason: Error) {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        let waiting = pending
        pending = [:]
        for (_, c) in waiting { c.resume(throwing: reason) }
    }

    private func startHeartbeat(gen: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, gen == self.generation, !Task.isCancelled else { return }
                do { _ = try await self.request("ping", timeout: 30) }
                catch { if gen == self.generation { self.closeSocket(reason: GatewayError.timeout("heartbeat")) }; return }
            }
        }
    }

    // MARK: Requests

    func request(_ method: String, _ params: [String: Any] = [:], timeout: TimeInterval = 120) async throws -> [String: Any] {
        guard let socket else { throw GatewayError.notConnected }
        nextId += 1
        let id = "t\(nextId)"
        let frame: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self)
        let result: Any? = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            Task {
                do { try await socket.send(.string(text)) }
                catch { if let c = self.pending.removeValue(forKey: id) { c.resume(throwing: error) } }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if let c = self.pending.removeValue(forKey: id) { c.resume(throwing: GatewayError.timeout(method)) }
            }
        }
        return result as? [String: Any] ?? [:]
    }

    /// False when there is no socket. A send that fails later means the socket died; the request
    /// it answered is still open on the server and comes back with the replay.
    @discardableResult
    private func send(frame: [String: Any]) -> Bool {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: frame) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        Task { try? await socket.send(.string(text)) }
        return true
    }

    private func serverRequest(id: String, method: String, params: [String: Any], replayed: Bool) -> ServerRequest {
        ServerRequest(id: id, method: method, params: params, replayed: replayed) { [weak self] result, failure in
            var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
            if let result { reply["result"] = result }
            if let failure { reply["error"] = ["code": failure.0, "message": failure.1] }
            return self?.send(frame: reply) ?? false
        }
    }

    // MARK: Inbound frames

    private func handle(text: String) {
        guard let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        let method = frame["method"] as? String
        if let id = frame["id"] as? String, let method, method != "event" {
            deliver(serverRequest(id: id, method: method, params: frame["params"] as? [String: Any] ?? [:], replayed: false))
            return
        }
        if let idValue = frame["id"], !(idValue is NSNull) {
            let id = (idValue as? String) ?? String(describing: idValue)
            guard let cont = pending.removeValue(forKey: id) else { return }
            if let err = frame["error"] as? [String: Any] {
                cont.resume(throwing: GatewayError.rpc(code: err["code"] as? Int, message: err["message"] as? String ?? "RPC error"))
            } else {
                deliverOpenRequests(frame["result"])
                cont.resume(returning: frame["result"])
            }
            return
        }
        if method == "event", let params = frame["params"] as? [String: Any], let event = GatewayEvent(params: params) {
            if event.type == "gateway.ready" {
                let epoch = event.string("replay_epoch")
                if let epoch, let old = replayEpoch, old != epoch { adoptEpoch(epoch) } else if replayEpoch == nil { replayEpoch = epoch }
                Task {
                    let caps = try? await self.request("client.capabilities", ["server_requests": true])
                    self.declinesNotShown = caps?["declines_not_shown"] as? Bool ?? false
                }
            }
            if let hold = replayHold, let sid = event.sessionId, hold[sid] != nil, event.seq != nil {
                replayHold?[sid]?.append(event)
                return
            }
            dispatchIfNewer(event)
        }
    }

    /// Requests only a Hermes Desktop window can answer: its terminal, preview, window and tour.
    private static let desktopOnly: Set<String> = ["terminal.read", "preview.read", "preview.act", "window.read", "tour"]

    private func deliver(_ request: ServerRequest) {
        guard onServerRequest?(request) != true else { return }
        // Hermes 0.21 sends a request to the one client that holds the session, so refusing is
        // right. A server that shares it between clients takes 4404 as "not shown here" and
        // leaves it open for the Desktop window, where any other error would settle it.
        if declinesNotShown, Self.desktopOnly.contains(request.method) {
            request.fail(code: 4404, message: "not shown on this client")
        } else {
            request.fail(code: -32601, message: "no handler for server request: \(request.method)")
        }
    }

    /// `session.resume` and `session.events.since` list still-open server requests to re-render.
    private func deliverOpenRequests(_ result: Any?) {
        guard let entries = (result as? [String: Any])?["open_requests"] as? [[String: Any]] else { return }
        for e in entries {
            guard let id = e["id"] as? String, let method = e["method"] as? String else { continue }
            deliver(serverRequest(id: id, method: method, params: e["params"] as? [String: Any] ?? [:], replayed: true))
        }
    }

    private func dispatchIfNewer(_ event: GatewayEvent) {
        if let sid = event.sessionId, let seq = event.seq {
            if seq <= (lastSeenSeq[sid] ?? 0) { return }
            lastSeenSeq[sid] = seq
        }
        onEvent?(event)
    }

    // MARK: Replay

    private func adoptEpoch(_ epoch: String) {
        replayEpoch = epoch
        let sessions = Array(lastSeenSeq.keys)
        lastSeenSeq = [:]
        onServerRestart?()
        for sid in sessions { onResync?(sid) }
    }

    private func replayAfterReconnect() async {
        guard !lastSeenSeq.isEmpty else { return }
        var hold: [String: [GatewayEvent]] = [:]
        for sid in lastSeenSeq.keys { hold[sid] = [] }
        replayHold = hold
        defer { flushReplayHold() }
        for (sid, lastSeen) in lastSeenSeq {
            guard let result = try? await request("session.events.since", ["session_id": sid, "last_seen": lastSeen], timeout: 30) else {
                // The gateway may have dropped the live session while we were away; reload it.
                onResync?(sid)
                continue
            }
            if let epoch = result["epoch"] as? String, let old = replayEpoch, epoch != old {
                adoptEpoch(epoch)
                return
            }
            if result["truncated"] as? Bool == true { onResync?(sid) }
            if let open = result["open_requests"] as? [[String: Any]] {
                onOpenRequests?(sid, Set(open.compactMap { $0["id"] as? String }))
            }
            for raw in result["events"] as? [[String: Any]] ?? [] {
                if let e = GatewayEvent(params: raw, replayed: true) { dispatchIfNewer(e) }
            }
        }
    }

    private func flushReplayHold() {
        guard let hold = replayHold else { return }
        replayHold = nil
        for (_, events) in hold { for e in events { dispatchIfNewer(e) } }
    }
}
