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
    /// Names of text files inlined into this turn (their contents ride in the sent input).
    var fileNames: [String] = []
    var isSteer = false
    var toolName: String?
    var toolResult: String?
    var toolError = false
    var toolDuration: Double?
    var toolCallId: String?
    var isStreaming = false
}

@Observable @MainActor
final class ChatStore {
    private static let activeRunKey = "hermes.activeRun"

    var session: HermesSession?
    var items: [ChatItem] = []
    var isRunning = false
    var isLoadingHistory = false
    var pendingApproval: ApprovalRequest?
    var error: String?

    private(set) var runId: String?
    private var streamTask: Task<Void, Never>?

    var client: HermesClient?

    // MARK: Session lifecycle

    func startNewChat() {
        cancelStream()
        session = nil
        items = []
        pendingApproval = nil
        error = nil
    }

    func open(_ s: HermesSession) async {
        guard let client else { return }
        cancelStream()
        session = s
        items = []
        pendingApproval = nil
        error = nil
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            items = Self.items(from: try await client.messages(sessionId: s.id))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reloadHistory() async {
        guard let client, let session else { return }
        if let msgs = try? await client.messages(sessionId: session.id) {
            items = Self.items(from: msgs)
        }
    }

    // MARK: Sending

    /// `files` are text documents; the API has no upload, so their contents are inlined after the message.
    func send(_ text: String, images: [UIImage] = [], files: [(name: String, text: String)] = []) async {
        guard let client, !isRunning else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty || !files.isEmpty else { return }
        error = nil
        do {
            if session == nil {
                session = try await client.createSession(title: nil)
            }
            guard let session else { return }
            let history = transcriptHistory()
            items.append(ChatItem(kind: .user, text: text, images: images, fileNames: files.map(\.name)))
            isRunning = true
            var input = text.isEmpty ? (files.isEmpty ? "(see attached image)" : "See the attached file(s).") : text
            for f in files {
                input += "\n\n--- Attached file: \(f.name) ---\n```\n\(f.text)\n```"
            }
            let dataURLs = images.compactMap { ImageEncoding.dataURL($0) }
            let id = try await client.createRun(
                input: input, imageDataURLs: dataURLs, history: history, sessionId: session.id)
            beginTracking(runId: id, sessionId: session.id)
            streamTask = Task { [weak self] in await self?.consume(runId: id, client: client) }
        } catch {
            self.error = error.localizedDescription
            isRunning = false
        }
    }

    /// Prior user/assistant turns as plain `{role, content}` pairs for `conversation_history`.
    /// Tool rows, reasoning and steer messages are not turns and are left out.
    private func transcriptHistory() -> [[String: String]] {
        items.compactMap { item in
            switch item.kind {
            case .user where !item.isSteer && !item.text.isEmpty: return ["role": "user", "content": item.text]
            case .assistant where !item.text.isEmpty: return ["role": "assistant", "content": item.text]
            default: return nil
            }
        }
    }

    /// Inject guidance into the running turn without stopping it.
    func steer(_ text: String) async {
        guard let client, let runId, isRunning else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await client.steer(runId: runId, text: text)
            items.append(ChatItem(kind: .user, text: text, isSteer: true))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() async {
        guard let client, let runId else { return }
        try? await client.stopRun(id: runId)
    }

    func respond(to approval: ApprovalRequest, choice: String) async {
        guard let client else { return }
        do {
            try await client.approve(runId: approval.runId, choice: choice, requestId: approval.requestId)
            if pendingApproval == approval { pendingApproval = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        runId = nil
        isRunning = false
        finishStreamingRows()
    }

    // MARK: Run tracking and resume

    private func beginTracking(runId: String, sessionId: String) {
        self.runId = runId
        UserDefaults.standard.set([runId, sessionId], forKey: Self.activeRunKey)
    }

    private func endTracking() {
        runId = nil
        isRunning = false
        pendingApproval = nil
        UserDefaults.standard.removeObject(forKey: Self.activeRunKey)
    }

    /// On launch or return to foreground: if a run was in flight when the app went away, pick it
    /// back up. Hermes drops the event queue once a subscriber disconnects, so the run is followed
    /// by polling its status and then reloading the session transcript.
    func resumeIfNeeded() async {
        guard let client else { return }
        if let task = streamTask, !task.isCancelled, isRunning { return } // stream still alive
        guard let saved = UserDefaults.standard.stringArray(forKey: Self.activeRunKey), saved.count == 2 else { return }
        let (savedRun, savedSession) = (saved[0], saved[1])
        if session?.id != savedSession {
            let s = (try? await client.getSession(id: savedSession)) ?? HermesSession(id: savedSession)
            await open(s)
        }
        runId = savedRun
        isRunning = true
        streamTask = Task { [weak self] in await self?.follow(runId: savedRun, client: client) }
    }

    /// Poll `GET /v1/runs/{id}` until the run ends, surfacing approval prompts, then refresh history.
    private func follow(runId: String, client: HermesClient) async {
        defer { if self.runId == runId { endTracking() } }
        while !Task.isCancelled {
            guard let status = try? await client.runStatus(id: runId) else { break } // gone: history is the truth
            if status.status == "waiting_for_approval", let a = status.approval {
                let req = ApprovalRequest(runId: runId, fields: a)
                if pendingApproval != req { pendingApproval = req }
            } else if pendingApproval?.runId == runId {
                pendingApproval = nil
            }
            if status.isTerminal { break }
            try? await Task.sleep(for: .seconds(2))
        }
        if !Task.isCancelled { await reloadHistory() }
    }

    // MARK: Event stream

    private func consume(runId: String, client: HermesClient) async {
        var sawTerminal = false
        do {
            for try await event in client.events(runId: runId) {
                if Task.isCancelled { break }
                apply(event, runId: runId)
                if event.name.hasPrefix("run.") && event.name != "run.started" && event.name != "run.steered" { sawTerminal = true }
            }
        } catch {
            if Task.isCancelled { return }
            // Connection dropped mid-run: fall back to polling the run instead of giving up.
            finishStreamingRows()
            items.append(ChatItem(kind: .notice, text: "Connection lost, following run…"))
            await follow(runId: runId, client: client)
            return
        }
        finishStreamingRows()
        if !sawTerminal && !Task.isCancelled {
            // Stream closed without a terminal event (e.g. events already flushed): resolve by polling.
            await follow(runId: runId, client: client)
            return
        }
        endTracking()
    }

    private func apply(_ e: RunEvent, runId: String) {
        switch e.name {
        case "message.delta":
            appendAssistant(e.string("delta") ?? "")

        case "message.interim":
            // Mid-turn commentary; skip when it was already streamed as deltas.
            if e.bool("already_streamed") != true, let t = e.string("text"), !t.isEmpty {
                items.append(ChatItem(kind: .commentary, text: t))
            }

        case "reasoning.available":
            // Some backends echo the final answer here; skip it when it just repeats streamed text.
            let text = e.string("text") ?? ""
            let streamed = items.last(where: { $0.kind == .assistant })?.text ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines) != streamed.trimmingCharacters(in: .whitespacesAndNewlines) {
                appendReasoning(text)
            }

        case "tool.started":
            items.append(ChatItem(kind: .tool, text: e.string("preview") ?? "", toolName: e.string("tool"), isStreaming: true))

        case "tool.completed":
            let name = e.string("tool")
            if let i = items.lastIndex(where: { $0.kind == .tool && $0.isStreaming && ($0.toolName == name || name == nil) }) {
                items[i].isStreaming = false
                items[i].toolResult = e.string("preview")
                items[i].toolError = e.bool("error") ?? false
                items[i].toolDuration = e.double("duration")
            }

        case "subagent.start":
            items.append(ChatItem(kind: .notice, text: "Delegating: \(e.string("goal") ?? e.string("preview") ?? "subagent started")"))

        case "subagent.complete":
            let status = e.string("status") ?? "done"
            items.append(ChatItem(kind: .notice, text: "Subagent \(status): \(e.string("summary") ?? "")"))

        case "approval.request":
            pendingApproval = ApprovalRequest(runId: runId, event: e)

        case "approval.responded":
            pendingApproval = nil

        case "run.completed":
            finishStreamingRows()
            if let output = e.string("output"), !output.isEmpty {
                if let i = items.lastIndex(where: { $0.kind == .assistant }) {
                    items[i].text = output
                } else {
                    items.append(ChatItem(kind: .assistant, text: output))
                }
            }

        case "run.failed", "run.interrupted":
            finishStreamingRows()
            items.append(ChatItem(kind: .error, text: e.string("error") ?? "Run \(e.name.dropFirst(4))"))

        case "run.cancelled":
            finishStreamingRows()
            items.append(ChatItem(kind: .notice, text: "Stopped"))

        case "error":
            items.append(ChatItem(kind: .error, text: e.string("message") ?? "Unknown error"))

        default:
            break
        }
    }

    private func appendAssistant(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let last = items.last, last.kind == .assistant, last.isStreaming {
            items[items.count - 1].text += delta
        } else {
            items.append(ChatItem(kind: .assistant, text: delta, isStreaming: true))
        }
    }

    private func appendReasoning(_ text: String) {
        guard !text.isEmpty else { return }
        if let last = items.last, last.kind == .reasoning, last.isStreaming {
            items[items.count - 1].text += text
        } else {
            items.append(ChatItem(kind: .reasoning, text: text, isStreaming: true))
        }
    }

    private func finishStreamingRows() {
        for i in items.indices where items[i].isStreaming { items[i].isStreaming = false }
    }

    // MARK: History mapping

    static func items(from messages: [HermesMessage]) -> [ChatItem] {
        var out: [ChatItem] = []
        var toolRowByCallId: [String: Int] = [:]
        for m in messages {
            switch m.role {
            case "user":
                let images = m.imageURLs.compactMap(ImageEncoding.image(fromDataURL:))
                out.append(ChatItem(kind: .user, text: m.text, images: images))
            case "assistant":
                if let r = m.reasoningText { out.append(ChatItem(kind: .reasoning, text: r)) }
                if !m.text.isEmpty { out.append(ChatItem(kind: .assistant, text: m.text)) }
                for call in m.toolCalls ?? [] {
                    out.append(ChatItem(kind: .tool, text: call.function?.arguments ?? "", toolName: call.function?.name, toolCallId: call.id))
                    if let id = call.id { toolRowByCallId[id] = out.count - 1 }
                }
            case "tool":
                if let id = m.toolCallId, let i = toolRowByCallId[id] {
                    out[i].toolResult = m.text
                } else {
                    out.append(ChatItem(kind: .tool, text: "", toolName: m.toolName, toolResult: m.text))
                }
            default:
                break // system prompts and hidden rows are not shown
            }
        }
        return out
    }
}
