import Foundation
import os

/// One reply's worth of streaming speech over the dashboard's `/api/audio/speak-stream`
/// WebSocket. Text goes in as sentences arrive (`{"text": …}`, then `{"done": true}`); the server
/// synthesises sentence by sentence and sends raw PCM back as binary frames while it works, after
/// a `{"type":"start","sample_rate":…,"channels":…}` frame and before `{"type":"end"}`. A server
/// with no streaming TTS provider answers `{"type":"fallback"}` and closes. Each upgrade needs a
/// fresh single-use ticket, so a stream is opened per reply, not per sentence.
@MainActor
final class SpeakStream {
    enum Event {
        case start(sampleRate: Double, channels: Int)
        case audio(Data)
        case end
        case fallback
        case closed(Error)
    }

    var onEvent: ((Event) -> Void)?
    /// Sentences handed to this stream, for re-speaking elsewhere if it fails before any audio.
    private(set) var sent: [String] = []
    private(set) var gotAudio = false
    /// No more text will be sent (`done` sent or queued).
    private(set) var finished = false
    /// The server has said `end`, or the socket is gone: nothing more will arrive.
    private(set) var ended = false

    private static let log = Logger(subsystem: "com.sainaney.talaria", category: "voice")
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var connectTask: Task<Void, Never>?
    private var isOpen = false
    private var outbox: [String] = []
    private var doneQueued = false

    init(auth: GatewayAuth) {
        connectTask = Task { [weak self] in
            do {
                let ticket = try await auth.wsTicket()
                guard let self, !Task.isCancelled else { return }
                let t = session.webSocketTask(with: auth.webSocketURL(path: "/api/audio/speak-stream", ticket: ticket))
                t.resume()
                task = t
                await receiveLoop(t)
            } catch {
                self?.close(with: error)
            }
        }
    }

    func send(_ text: String) {
        guard !finished, !ended else { return }
        sent.append(text)
        if isOpen { post(["text": text + " "]) } else { outbox.append(text) }
    }

    /// No more text: the server flushes what it has and answers `end` once synthesis is done.
    func finish() {
        guard !finished else { return }
        finished = true
        if isOpen { post(["done": true]) } else { doneQueued = true }
    }

    /// Barge-in: tell the server to stop synthesising and drop the socket.
    func stop() {
        onEvent = nil
        finished = true
        ended = true
        if isOpen { post(["stop": true]) }
        connectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while !Task.isCancelled, !ended {
            let message: URLSessionWebSocketTask.Message
            do { message = try await t.receive() } catch { close(with: error); return }
            switch message {
            case .data(let d):
                if !d.isEmpty { gotAudio = true; onEvent?(.audio(d)) }
            case .string(let s):
                handle(json: s)
            @unknown default:
                break
            }
        }
    }

    private func handle(json: String) {
        let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
        switch obj["type"] as? String {
        case "start":
            isOpen = true
            let rate = (obj["sample_rate"] as? Double) ?? Double((obj["sample_rate"] as? Int) ?? 24000)
            let channels = max(1, (obj["channels"] as? Int) ?? 1)
            onEvent?(.start(sampleRate: rate, channels: channels))
            for text in outbox { post(["text": text + " "]) }
            outbox = []
            if doneQueued { post(["done": true]) }
        case "end":
            ended = true
            onEvent?(.end)
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
        case "fallback":
            ended = true
            onEvent?(.fallback)
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
        default:
            Self.log.debug("speak-stream: ignoring \(json, privacy: .public)")
        }
    }

    private func close(with error: Error) {
        guard !ended else { return }
        ended = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onEvent?(.closed(error))
    }

    private func post(_ obj: [String: Any]) {
        guard let t = task, let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        t.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in self?.close(with: error) }
        }
    }
}
