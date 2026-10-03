import Foundation
import Observation
import UIKit

/// One row in the transcript. Assistant text, reasoning and tool calls are separate rows so the
/// order in which the agent thought, acted and answered is preserved.
struct ChatItem: Identifiable {
    enum Kind { case user, assistant, reasoning, tool, commentary, notice, error }

    let id = UUID()
    var kind: Kind
    var text: String = ""
    var images: [UIImage] = []
    var fileNames: [String] = []
    var isSteer = false
    var isQueued = false
    var isVoice = false
    /// Typed on another client (web dashboard, TUI) while this session was open here.
    var isRemote = false
    var toolId: String?
    var toolName: String?
    var toolResult: String?
    var toolError = false
    var toolDuration: Double?
    var isStreaming = false
}

/// What the voice layer needs to know about the open session, in order.
enum ChatSignal {
    case turnStarted
    case assistantDelta(String)
    case turnComplete(final: String?, status: String?)
    case requestsChanged
}

@Observable @MainActor
final class ChatStore {
    private static let draftKey = "__new__"
    private static let lastSessionKey = "hermes.lastSession"

    var session: HermesSession?
    private var transcripts: [String: [ChatItem]] = [:]
    /// Live session ids with a turn in progress.
    private var running: Set<String> = []
    /// Transient status line per live session (compacting, tool progress, …).
    private var statusLines: [String: String] = [:]
    /// Model and reasoning effort per live session, from `session.info`.
    private var liveInfo: [String: (model: String, effort: String)] = [:]
    /// Sessions where this client just submitted a prompt, so the next message.start is ours.
    private var expectingTurnStart: Set<String> = []
    var isLoadingHistory = false
    /// Open requests from the agent, oldest first. The server can hold several at once and each
    /// waits for its own reply, so they queue; the sheets show the first.
    private(set) var approvals: [ApprovalRequest] = [] { didSet { if approvals != oldValue { signal?(.requestsChanged) } } }
    private(set) var clarifies: [ClarifyRequest] = [] { didSet { if clarifies != oldValue { signal?(.requestsChanged) } } }
    private(set) var secrets: [SecretRequest] = []
    var pendingApproval: ApprovalRequest? { approvals.first }
    var pendingClarify: ClarifyRequest? { clarifies.first }
    var pendingSecret: SecretRequest? { secrets.first }
    /// Why the last answer did not go out; shown on the request's sheet.
    private(set) var requestError: String?
    var error: String?
    /// The open chat is shown but not attached yet (the socket was down); retried on reconnect.
    private(set) var needsOpen = false
    /// Counts opens, so a slow resume cannot land on a chat the person has since left.
    private var openGeneration = 0
    /// The bubble of a send still on its way; taken back if the send fails.
    private var unsentBubble: UUID?

    /// What is typed but not sent, per chat (by stored id; the unsent new chat has its own slot),
    /// so it survives leaving the chat or switching to voice.
    struct Draft {
        var text = ""
        var attachments: [Attachment] = []
    }
    private var drafts: [String: Draft] = [:]
    private var draftSlot: String { session?.id ?? Self.draftKey }
    var draft: Draft {
        get { drafts[draftSlot] ?? Draft() }
        set { drafts[draftSlot] = newValue.text.isEmpty && newValue.attachments.isEmpty ? nil : newValue }
    }

    var client: GatewayClient?
    var onSessionCreated: ((HermesSession) -> Void)?
    var onTitleChanged: ((String, String) -> Void)?
    /// Fired for the open session only; see `ChatSignal`.
    var signal: ((ChatSignal) -> Void)?

    private var currentKey: String { session?.liveId ?? Self.draftKey }

    var items: [ChatItem] {
        get { transcripts[currentKey] ?? [] }
        set { transcripts[currentKey] = newValue }
    }
    var isRunning: Bool { session.map { running.contains($0.liveId) } ?? false }
    func isRunning(_ s: HermesSession) -> Bool { running.contains(s.liveId) || running.contains(s.id) }
    var statusText: String? { session.flatMap { statusLines[$0.liveId] } }

    /// "glm-5.3 · Med" style label for the composer pill; nil until a session reports it.
    var modelLabel: String? {
        guard let info = session.flatMap({ liveInfo[$0.liveId] }) ?? liveInfo.values.first else { return nil }
        let effort: String
        switch info.effort.lowercased() {
        case "": effort = ""
        case "medium": effort = "Med"
        default: effort = info.effort.prefix(1).uppercased() + info.effort.dropFirst()
        }
        return effort.isEmpty ? info.model : "\(info.model) · \(effort)"
    }

    /// The open session's model and reasoning effort as the server last reported them.
    var currentInfo: (model: String, effort: String)? { session.flatMap { liveInfo[$0.liveId] } }

    private func recordInfo(_ info: [String: Any]?, for liveId: String) {
        guard let info, let model = info["model"] as? String, !model.isEmpty else { return }
        liveInfo[liveId] = (model, info["reasoning_effort"] as? String ?? "")
    }

    // MARK: Session lifecycle

    func startNewChat() {
        openGeneration += 1
        needsOpen = false
        isLoadingHistory = false
        session = nil
        transcripts[Self.draftKey] = []
        error = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSessionKey)
    }

    /// Attach to a stored session. `session.resume` reuses the live agent when one exists, so an
    /// in-flight turn keeps streaming into this transcript.
    func open(_ s: HermesSession) async {
        guard let client else { return }
        openGeneration += 1
        let gen = openGeneration
        error = nil
        // Show this chat at once, so a resume that fails or is slow never leaves the previous
        // chat's transcript (and its sends) under this one's title.
        if session?.id != s.id { session = s }
        isLoadingHistory = true
        guard client.isConnected else { needsOpen = true; return } // reopened when the socket is back
        do {
            let r = try await client.request("session.resume", ["session_id": s.id], timeout: 180)
            guard gen == openGeneration else { return }
            var live = s
            live.liveId = r["session_id"] as? String ?? s.id
            if let info = r["info"] as? [String: Any], let t = info["title"] as? String, !t.isEmpty { live.title = t }
            session = live
            needsOpen = false
            UserDefaults.standard.set(s.id, forKey: Self.lastSessionKey)
            apply(resume: r, to: live.liveId)
        } catch {
            guard gen == openGeneration else { return }
            needsOpen = true
            self.error = error.localizedDescription
        }
        isLoadingHistory = false
    }

    /// The socket is back: attach the chat that was opened while it was down.
    func reopenIfNeeded() async {
        if needsOpen, let s = session { await open(s) }
    }

    /// Re-fetch a session's transcript after a replay gap or server restart. A restarted gateway
    /// hands the stored session a new live id; everything keyed by the old one moves over, or the
    /// next prompt would go to an id the gateway no longer has.
    func resync(liveId: String) async {
        guard let client, let s = session, s.liveId == liveId else { return }
        guard let r = try? await client.request("session.resume", ["session_id": s.id], timeout: 180) else { return }
        var current = liveId
        if let fresh = r["session_id"] as? String, !fresh.isEmpty, fresh != liveId {
            adopt(liveId: fresh, replacing: liveId)
            current = fresh
        }
        apply(resume: r, to: current)
    }

    private func adopt(liveId new: String, replacing old: String) {
        guard var s = session, s.liveId == old else { return }
        s.liveId = new
        session = s
        if let t = transcripts.removeValue(forKey: old) { transcripts[new] = t }
        if running.remove(old) != nil { running.insert(new) }
        if let l = statusLines.removeValue(forKey: old) { statusLines[new] = l }
        if let i = liveInfo.removeValue(forKey: old) { liveInfo[new] = i }
        if expectingTurnStart.remove(old) != nil { expectingTurnStart.insert(new) }
        client?.forgetSession(old)
    }

    private func apply(resume r: [String: Any], to liveId: String) {
        var rows = Self.items(from: (r["messages"] as? [[String: Any]] ?? []).compactMap(TranscriptMessage.init(row:)))
        let isRunning = (r["running"] as? Bool) ?? ((r["info"] as? [String: Any])?["running"] as? Bool) ?? false
        if isRunning, let inflight = r["inflight"] as? [String: Any] {
            if let u = inflight["user"] as? String, !u.isEmpty, rows.last?.kind != .user || rows.last?.text != u {
                rows.append(ChatItem(kind: .user, text: u))
            }
            if let a = inflight["assistant"] as? String, !a.isEmpty {
                rows.append(ChatItem(kind: .assistant, text: a, isStreaming: true))
            }
        }
        transcripts[liveId] = rows
        recordInfo(r["info"] as? [String: Any], for: liveId)
        if isRunning { running.insert(liveId) } else { running.remove(liveId) }
        // The open server requests themselves arrive via open_requests (absent when there are none).
        let open = (r["open_requests"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        reconcileRequests(session: liveId, open: Set(open))
    }

    /// Fetch the prompt of a turn that another client started on the open session.
    private func showRemotePrompt(liveId: String) async {
        guard let client, let s = session, s.liveId == liveId,
              let r = try? await client.request("session.resume", ["session_id": s.id], timeout: 60),
              let inflight = r["inflight"] as? [String: Any],
              let text = inflight["user"] as? String, !text.isEmpty else { return }
        var items = transcripts[liveId] ?? []
        if let last = items.last(where: { $0.kind == .user }), last.text == text { return }
        var item = ChatItem(kind: .user, text: text)
        item.isRemote = true
        // Place it before anything already streamed for this turn.
        if let i = items.lastIndex(where: { $0.kind == .user }) {
            let insertAt = items[(i + 1)...].firstIndex(where: { $0.isStreaming }) ?? items.endIndex
            items.insert(item, at: insertAt)
        } else {
            items.append(item)
        }
        transcripts[liveId] = items
    }

    func forget(_ s: HermesSession) {
        transcripts[s.liveId] = nil
        running.remove(s.liveId)
        drafts[s.id] = nil
        client?.forgetSession(s.liveId)
    }

    func lastOpenedSessionId() -> String? { UserDefaults.standard.string(forKey: Self.lastSessionKey) }

    // MARK: Sending

    /// Extra `prompt.submit` fields for a spoken turn: Hermes prepends a "you are being listened to"
    /// note to the model input, plus the recent exchange and whether the person cut the last reply off.
    struct VoiceTurn {
        var context: String?
        var interrupted = false
        var params: [String: Any] {
            var p: [String: Any] = ["surface": "voice-live"]
            if let context, !context.isEmpty { p["voice_context"] = context }
            if interrupted { p["interrupted"] = true }
            return p
        }
    }

    /// The last few spoken exchanges, newest last, for `voice_context`.
    func recentExchange(limit: Int = 6) -> String {
        items.filter { $0.kind == .user || $0.kind == .assistant }.suffix(limit).map {
            "\($0.kind == .user ? "User" : "Hermes"): \(String($0.text.prefix(300)))"
        }.joined(separator: "\n")
    }

    /// False when the message did not go out; the caller still has the text and gives it back
    /// to the composer.
    @discardableResult
    func send(_ text: String, images: [UIImage] = [], files: [(name: String, text: String)] = [], skills: SkillsStore? = nil, voice: VoiceTurn? = nil) async -> Bool {
        guard let client else { error = GatewayError.notConnected.localizedDescription; return false }
        // A reconnect in progress (server restart, network blip) usually completes within seconds.
        for _ in 0..<40 where !client.isConnected { try? await Task.sleep(for: .milliseconds(250)) }
        guard client.isConnected else { error = GatewayError.notConnected.localizedDescription; return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty || !files.isEmpty else { return true }
        error = nil
        do {
            if session == nil { try await createSession(client) }
            do {
                try await deliver(text, images: images, files: files, skills: skills, voice: voice, client: client)
            } catch let e as GatewayError where e.isSessionGone {
                // The gateway dropped the live session while the phone was away. Attach to the
                // stored one again, which hands out a new live id, and send once more.
                guard let stale = session?.liveId else { throw e }
                retractSend(in: stale)
                await resync(liveId: stale)
                try await deliver(text, images: images, files: files, skills: skills, voice: voice, client: client)
            }
            unsentBubble = nil
            return true
        } catch {
            self.error = error.localizedDescription
            if let sid = session?.liveId { retractSend(in: sid) }
            return false
        }
    }

    /// Undo what a failed send left behind: its bubble, the running mark and the expected turn start.
    private func retractSend(in sid: String) {
        if let id = unsentBubble { transcripts[sid]?.removeAll { $0.id == id } }
        unsentBubble = nil
        running.remove(sid)
        expectingTurnStart.remove(sid)
    }

    private func deliver(_ text: String, images: [UIImage], files: [(name: String, text: String)], skills: SkillsStore?, voice: VoiceTurn?, client: GatewayClient) async throws {
        guard let session else { return }
        let sid = session.liveId

        // Attachments are staged server-side before the prompt.
        for img in images {
            guard let jpeg = ImageEncoding.jpegData(img) else { continue }
            _ = try await client.request("image.attach_bytes", [
                "session_id": sid, "content_base64": jpeg.base64EncodedString(), "filename": "photo.jpg", "ext": "jpg"], timeout: 120)
        }
        var body = text
        for f in files {
            let dataURL = "data:text/plain;base64," + Data(f.text.utf8).base64EncodedString()
            if let r = try? await client.request("file.attach", ["session_id": sid, "data_url": dataURL, "name": f.name], timeout: 120),
               let ref = r["ref_text"] as? String, !ref.isEmpty {
                body += (body.isEmpty ? "" : "\n") + ref
            } else {
                body += "\n\n--- Attached file: \(f.name) ---\n```\n\(f.text)\n```"
            }
        }
        if body.isEmpty { body = "See the attached image." }

        let bubble = ChatItem(kind: .user, text: text.isEmpty ? body : text, images: images, fileNames: files.map(\.name), isVoice: voice != nil)
        transcripts[sid, default: []].append(bubble)
        unsentBubble = bubble.id

        // `/skill args` goes through the server's slash dispatcher, like the TUI; a few
        // built-ins (/model, /reasoning, …) are per-session settings, not prompts.
        var submitText = body
        if body.hasPrefix("/") {
            let name = String(body.dropFirst().prefix { !$0.isWhitespace })
            let arg = String(body.dropFirst(1 + name.count)).trimmingCharacters(in: .whitespaces)
            if Self.sessionSettingCommands.contains(name) {
                transcripts[sid, default: []].removeLast() // not a message; show the outcome instead
                if arg.isEmpty {
                    transcripts[sid, default: []].append(ChatItem(kind: .notice, text: "/\(name) needs a value"))
                } else if await setSessionConfig(name, arg) {
                    transcripts[sid, default: []].append(ChatItem(kind: .notice, text: "\(name) set to \(arg)"))
                }
                return
            }
            if skills?.skill(named: name) == nil, skills?.commands.contains(where: { $0.name == name }) == true {
                // Other built-ins (/help, /status, …) run server-side; the output is a notice.
                transcripts[sid, default: []].removeLast()
                do {
                    let r = try await client.request("slash.exec", ["command": text, "session_id": sid], timeout: 120)
                    transcripts[sid, default: []].append(ChatItem(kind: .notice, text: r["output"] as? String ?? "(no output)"))
                } catch let e as GatewayError where e.isSessionGone {
                    throw e
                } catch {
                    transcripts[sid, default: []].append(ChatItem(kind: .notice, text: "/\(name): \(error.localizedDescription)"))
                }
                return
            }
            if let skills, skills.skill(named: name) != nil {
                let d = try await client.request("command.dispatch", ["name": name, "arg": arg, "session_id": sid], timeout: 60)
                switch d["type"] as? String {
                case "skill", "send":
                    if let m = d["message"] as? String, !m.isEmpty { submitText = m }
                    if let n = d["notice"] as? String, !n.isEmpty { transcripts[sid, default: []].append(ChatItem(kind: .notice, text: n)) }
                case "exec", "plugin":
                    transcripts[sid, default: []].append(ChatItem(kind: .notice, text: d["output"] as? String ?? "(no output)"))
                    return
                default:
                    if let m = d["message"] as? String, !m.isEmpty { submitText = m }
                }
            }
        }

        running.insert(sid)
        expectingTurnStart.insert(sid)
        var params: [String: Any] = ["session_id": sid, "text": submitText]
        if let voice { params.merge(voice.params) { a, _ in a } }
        let r = try await client.request("prompt.submit", params, timeout: 60)
        if let status = r["status"] as? String, status == "queued" {
            transcripts[sid, default: []].append(ChatItem(kind: .notice, text: "Queued behind the running turn"))
        }
    }

    private func createSession(_ client: GatewayClient) async throws {
        let r = try await client.request("session.create", [:], timeout: 60)
        guard let liveId = r["session_id"] as? String else { throw GatewayError.badFrame }
        let stored = r["stored_session_id"] as? String ?? liveId
        let created = HermesSession(id: stored, liveId: liveId)
        transcripts[liveId] = transcripts[Self.draftKey] ?? []
        transcripts[Self.draftKey] = []
        if let d = drafts.removeValue(forKey: Self.draftKey) { drafts[stored] = d }
        recordInfo(r["info"] as? [String: Any], for: liveId)
        session = created
        UserDefaults.standard.set(stored, forKey: Self.lastSessionKey)
        onSessionCreated?(created)
    }

    /// Open a live session now if none exists, so per-session settings can be applied before the first prompt.
    func ensureSession() async {
        guard session == nil, let client, client.isConnected else { return }
        do { try await createSession(client) } catch { self.error = error.localizedDescription }
    }

    /// Slash commands that map to `config.set` on the session rather than a prompt.
    static let sessionSettingCommands: Set<String> = ["model", "reasoning", "fast", "yolo", "approval_mode", "verbose"]

    /// Per-session runtime setting, the same as the TUI's `/model` and `/reasoning`.
    @discardableResult
    func setSessionConfig(_ key: String, _ value: String) async -> Bool {
        await setSessionConfigResult(key, value) != nil
    }

    /// Same, returning the server's reply (model switches report `confirm_required` / `warning`).
    func setSessionConfigResult(_ key: String, _ value: String, confirmed: Bool = false) async -> [String: Any]? {
        guard let client, let sid = session?.liveId else { return nil }
        do {
            // scope is explicit: without a resolvable session the server would write the global config.
            var params: [String: Any] = ["key": key, "value": value, "session_id": sid, "scope": "session"]
            if confirmed { params["confirm_expensive_model"] = true }
            return try await client.request("config.set", params, timeout: 60)
        } catch {
            transcripts[sid, default: []].append(ChatItem(kind: .notice, text: "Could not set \(key) to \(value): \(error.localizedDescription)"))
            return nil
        }
    }

    /// Providers and models available to the open session (creates the session if needed).
    func modelOptions(refresh: Bool) async throws -> ModelOptions {
        await ensureSession()
        guard let client, let sid = session?.liveId else { throw GatewayError.notConnected }
        let r = try await client.request("model.options", ["session_id": sid, "refresh": refresh], timeout: 60)
        guard let o = ModelOptions(payload: r) else { throw GatewayError.badFrame }
        return o
    }

    /// Queue a message to run after the current turn (FIFO, never a live correction). False when
    /// it was not queued (the turn ended meanwhile, or the call failed).
    @discardableResult
    func enqueue(_ text: String, voice: VoiceTurn? = nil) async -> Bool {
        guard let client, let sid = session?.liveId, isRunning else { return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        var item = ChatItem(kind: .user, text: text)
        item.isQueued = true
        item.isVoice = voice != nil
        transcripts[sid, default: []].append(item)
        let expecting = expectingTurnStart.insert(sid).inserted
        do {
            var params: [String: Any] = ["session_id": sid, "text": text, "queued": true]
            if let voice { params.merge(voice.params) { a, _ in a } }
            _ = try await client.request("prompt.submit", params, timeout: 60)
            return true
        } catch {
            self.error = error.localizedDescription
            transcripts[sid]?.removeAll { $0.id == item.id }
            if expecting { expectingTurnStart.remove(sid) }
            return false
        }
    }

    /// Replace the running turn's direction with new text (interrupts and continues). False when
    /// the call did not go through.
    @discardableResult
    func redirect(_ text: String, voice: VoiceTurn? = nil) async -> Bool {
        guard let client, let sid = session?.liveId, isRunning else { return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        var item = ChatItem(kind: .user, text: text)
        item.isSteer = true
        item.isVoice = voice != nil
        transcripts[sid, default: []].append(item)
        let expecting = expectingTurnStart.insert(sid).inserted
        do {
            // session.redirect validates strictly and rejects the voice-live fields; the surface
            // set by the last prompt.submit still applies to the redirected turn.
            _ = try await client.request("session.redirect", ["session_id": sid, "text": text], timeout: 60)
            return true
        } catch {
            self.error = error.localizedDescription
            transcripts[sid]?.removeAll { $0.id == item.id }
            if expecting { expectingTurnStart.remove(sid) }
            return false
        }
    }

    /// Inject guidance into the running turn without stopping it. Returns false when the server
    /// would not take it (turn too far along), so the caller can queue instead.
    @discardableResult
    func steer(_ text: String, viaVoice: Bool = false) async -> Bool {
        guard let client, let sid = session?.liveId, isRunning else { return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        do {
            let r = try await client.request("session.steer", ["session_id": sid, "text": text], timeout: 30)
            if r["status"] as? String == "rejected" { return false }
            transcripts[sid, default: []].append(ChatItem(kind: .user, text: text, isSteer: true, isVoice: viaVoice))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func stop() async {
        guard let client, let sid = session?.liveId else { return }
        _ = try? await client.request("session.interrupt", ["session_id": sid], timeout: 30)
    }

    // MARK: Server requests (approval, clarify, masked prompts)

    /// Returns false for request kinds this client does not handle.
    func handle(serverRequest r: ServerRequest) -> Bool {
        // A request replayed after a reconnect may already be waiting here; keep the one shown.
        switch r.method {
        case "approval":
            if !approvals.contains(where: { $0.id == r.id }) { approvals.append(ApprovalRequest(request: r)) }
        case "clarify":
            if !clarifies.contains(where: { $0.id == r.id }) { clarifies.append(ClarifyRequest(request: r)) }
        case "sudo", "secret", "vault.unlock_prompt":
            if !secrets.contains(where: { $0.id == r.id }) { secrets.append(SecretRequest(request: r)) }
        default:
            return false
        }
        return true
    }

    /// False when the answer could not be sent (no socket). The request then stays up to be
    /// answered again, instead of the turn waiting on an answer that never left the phone.
    @discardableResult
    func respond(to approval: ApprovalRequest, choice: String) -> Bool {
        guard approval.request?.respond(["choice": choice]) != false else { return unsent() }
        requestError = nil
        approvals.removeAll { $0.id == approval.id }
        return true
    }

    @discardableResult
    func respond(to clarify: ClarifyRequest, answer: String) -> Bool {
        guard clarify.request.respond(["answer": answer]) else { return unsent() }
        requestError = nil
        clarifies.removeAll { $0.id == clarify.id }
        return true
    }

    /// An empty value skips the prompt.
    @discardableResult
    func respond(to secret: SecretRequest, value: String) -> Bool {
        guard secret.request.respond(["value": value]) else { return unsent() }
        requestError = nil
        secrets.removeAll { $0.id == secret.id }
        return true
    }

    private func unsent() -> Bool {
        requestError = "Not connected to Hermes. Answer again in a moment."
        return false
    }

    /// After a resume or a replay the server lists what is still open for a session; anything
    /// else held for it was answered on another client or timed out while the phone was away.
    func reconcileRequests(session sid: String, open: Set<String>) {
        approvals.removeAll { $0.sessionId == sid && !open.contains($0.id) }
        clarifies.removeAll { $0.sessionId == sid && !open.contains($0.id) }
        secrets.removeAll { $0.sessionId == sid && !open.contains($0.id) }
    }

    /// The gateway restarted: nothing it asked is waiting any more.
    func dropRequests() {
        approvals = []
        clarifies = []
        secrets = []
        requestError = nil
    }

    private func dropRequest(id: String?) {
        requestError = nil
        approvals.removeAll { $0.id == id }
        clarifies.removeAll { $0.id == id }
        secrets.removeAll { $0.id == id }
    }

    // MARK: Events

    func handle(event e: GatewayEvent) {
        if e.type == "request.cancel" { dropRequest(id: e.string("id")); return }
        guard let sid = e.sessionId else { return }
        var items: [ChatItem] { get { transcripts[sid] ?? [] } set { transcripts[sid] = newValue } }
        let isOpen = sid == currentKey

        switch e.type {
        case "message.start":
            if isOpen { Bench.mark("message_start") }
            running.insert(sid)
            statusLines[sid] = nil
            if let i = items.firstIndex(where: { $0.kind == .user && $0.isQueued }) { items[i].isQueued = false }
            if expectingTurnStart.remove(sid) == nil, isOpen {
                // Started by another client: pull its prompt so the transcript stays complete.
                Task { await self.showRemotePrompt(liveId: sid) }
            }
            if isOpen { signal?(.turnStarted) }

        case "message.delta":
            if isOpen, !(items.last?.kind == .assistant && items.last?.isStreaming == true) { Bench.mark("first_delta") }
            appendStreaming(kind: .assistant, e.string("text") ?? "", sessionId: sid)
            if isOpen, let t = e.string("text"), !t.isEmpty { signal?(.assistantDelta(t)) }

        case "reasoning.delta", "thinking.delta":
            appendStreaming(kind: .reasoning, e.string("text") ?? "", sessionId: sid)

        case "reasoning.available":
            let text = e.string("text") ?? ""
            let streamed = items.last(where: { $0.kind == .assistant })?.text ?? ""
            if !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != streamed.trimmingCharacters(in: .whitespacesAndNewlines) {
                finishStreaming(kind: .reasoning, sessionId: sid)
                items.append(ChatItem(kind: .reasoning, text: text))
            }

        case "message.interim":
            if e.bool("already_streamed") != true, let t = e.string("text"), !t.isEmpty {
                finishStreaming(kind: .assistant, sessionId: sid)
                items.append(ChatItem(kind: .commentary, text: t))
            }

        case "tool.start":
            if isOpen { Bench.mark("tool_start", "name=\(e.string("name") ?? "?")") }
            finishStreaming(kind: .reasoning, sessionId: sid)
            finishStreaming(kind: .assistant, sessionId: sid)
            let args = e.string("args_text") ?? e.string("preview")
                ?? (e.payload["args"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }.map { String(decoding: $0, as: UTF8.self) }
            items.append(ChatItem(kind: .tool, text: args ?? "", toolId: e.string("tool_id"), toolName: e.string("name"), isStreaming: true))

        case "tool.complete":
            if isOpen { Bench.mark("tool_end", "dur=\(e.double("duration_s").map { String(format: "%.2f", $0) } ?? "?")") }
            let toolId = e.string("tool_id")
            if let i = items.lastIndex(where: { $0.kind == .tool && ($0.toolId == toolId || (toolId == nil && $0.isStreaming)) }) {
                items[i].isStreaming = false
                let result = e.string("result_text") ?? e.string("summary") ?? (e.payload["result"] as? String)
                items[i].toolResult = result
                items[i].toolDuration = e.double("duration_s")
                items[i].toolError = result.map { $0.hasPrefix("Error") || $0.hasPrefix("BLOCKED") } ?? false
            }

        case "message.complete":
            if isOpen { Bench.mark("message_complete", "status=\(e.string("status") ?? "ok")") }
            finishAll(sessionId: sid)
            running.remove(sid)
            statusLines[sid] = nil
            let final = e.string("text") ?? ""
            if !final.isEmpty {
                if let i = items.lastIndex(where: { $0.kind == .assistant }), items.lastIndex(where: { $0.kind == .user }) ?? -1 < i {
                    items[i].text = final
                } else {
                    items.append(ChatItem(kind: .assistant, text: final))
                }
            }
            switch e.string("status") {
            case "error": items.append(ChatItem(kind: .error, text: e.string("error") ?? e.string("failure_reason") ?? "Turn failed"))
            case "interrupted": items.append(ChatItem(kind: .notice, text: "Stopped"))
            default: break
            }
            if let w = e.string("warning"), !w.isEmpty { items.append(ChatItem(kind: .notice, text: w)) }
            if isOpen { signal?(.turnComplete(final: final.isEmpty ? nil : final, status: e.string("status"))) }

        case "status.update":
            statusLines[sid] = e.string("text")

        case "session.title":
            if let t = e.string("title") { onTitleChanged?(e.string("session_id") ?? sid, t) }

        case "session.info":
            recordInfo(e.payload, for: sid)
            if let r = e.bool("running") { if r { running.insert(sid) } else { running.remove(sid); finishAll(sessionId: sid) } }

        case "error":
            items.append(ChatItem(kind: .error, text: e.string("message") ?? "Error"))

        case "notice":
            if let m = e.string("message") { items.append(ChatItem(kind: .notice, text: m)) }

        case "subagent.start":
            items.append(ChatItem(kind: .notice, text: "Delegating: \(e.string("goal") ?? "subagent")"))

        case "subagent.complete":
            items.append(ChatItem(kind: .notice, text: "Subagent \(e.string("status") ?? "done"): \(e.string("summary") ?? "")"))

        default:
            break
        }
    }

    private func appendStreaming(kind: ChatItem.Kind, _ text: String, sessionId sid: String) {
        guard !text.isEmpty else { return }
        var items = transcripts[sid] ?? []
        if let last = items.last, last.kind == kind, last.isStreaming {
            items[items.count - 1].text += text
        } else {
            if kind == .assistant { for i in items.indices where items[i].kind == .reasoning { items[i].isStreaming = false } }
            items.append(ChatItem(kind: kind, text: text, isStreaming: true))
        }
        transcripts[sid] = items
    }

    private func finishStreaming(kind: ChatItem.Kind, sessionId sid: String) {
        guard var items = transcripts[sid] else { return }
        for i in items.indices where items[i].kind == kind && items[i].isStreaming { items[i].isStreaming = false }
        transcripts[sid] = items
    }

    private func finishAll(sessionId sid: String) {
        guard var items = transcripts[sid] else { return }
        for i in items.indices where items[i].isStreaming { items[i].isStreaming = false }
        transcripts[sid] = items
    }

    // MARK: History mapping

    static func items(from messages: [TranscriptMessage]) -> [ChatItem] {
        var out: [ChatItem] = []
        for m in messages {
            if m.displayKind == "hidden" { continue }
            switch m.role {
            case "user":
                out.append(ChatItem(kind: .user, text: m.text))
            case "assistant":
                if let r = m.reasoning, !r.isEmpty { out.append(ChatItem(kind: .reasoning, text: r)) }
                if !m.text.isEmpty { out.append(ChatItem(kind: .assistant, text: m.text)) }
            case "tool":
                let args = m.args.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
                out.append(ChatItem(kind: .tool, text: args, toolName: m.name, toolResult: m.text))
            default:
                if !m.text.isEmpty { out.append(ChatItem(kind: .notice, text: m.text)) }
            }
        }
        return out
    }
}
