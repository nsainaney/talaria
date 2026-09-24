import Foundation
import Observation

/// Hands-free conversation with Hermes: listen, send, speak the reply, listen again. Talking over
/// a reply stops it. Permission and clarify requests are read aloud and can be answered by voice.
@Observable @MainActor
final class VoiceController {
    enum State: Equatable { case idle, listening, thinking, speaking }
    enum Answering: Equatable { case none, approval, clarify }

    private(set) var state: State = .idle
    private(set) var answering: Answering = .none
    /// Live text of the utterance being spoken by the person.
    private(set) var transcript = ""
    /// Microphone level 0…1 for the meter in the voice bar.
    private(set) var micLevel: Float = 0
    var error: String?
    var isActive: Bool { state != .idle }
    /// The microphone is ignored and nothing is sent; Hermes waits. Its current reply still finishes.
    private(set) var isPaused = false

    private let recognizer = SpeechRecognizer()
    private let speaker = HermesSpeaker()
    private var splitter = SpeechSentenceSplitter()
    private var silenceTask: Task<Void, Never>?
    private var workingCueTask: Task<Void, Never>?
    /// Set after a barge-in so the rest of the interrupted reply stays silent.
    private var muteReply = false
    /// Whether the person cut the last reply off; told to Hermes on the next turn.
    private var interruptedLastReply = false
    /// Session switched to the fast alias for voice, and what to restore afterwards.
    private var fastAppliedTo: String?
    private var restoreTo: (model: String, effort: String)?
    /// Words the phone itself said recently, to reject its own speech coming back through the mic.
    private var recentlySpoken: [(at: Date, words: Set<String>)] = []
    private unowned let chat: ChatStore
    private let skills: SkillsStore
    private let settings: ServerSettings

    /// Quiet gap after the transcript stops changing that ends an utterance. Longer while Hermes
    /// is already working, since nothing is waiting on the words and mid-thought pauses are common.
    private var endOfUtterance: Duration { chat.isRunning ? .seconds(2) : .milliseconds(1300) }
    /// Extra wait granted, at most twice, when the sentence so far clearly is not finished.
    private let unfinishedGrace: Duration = .seconds(1)
    private static let trailingConnectives: Set<String> = [
        "and", "or", "but", "so", "because", "then", "like", "example", "with", "to", "the", "a", "an",
        "of", "in", "on", "at", "for", "is", "are", "was", "if", "that", "which", "i", "we", "you", "it",
        "um", "uh", "er", "also", "plus", "minus", "not", "no", "very", "really", "just",
    ]

    init(chat: ChatStore, skills: SkillsStore, settings: ServerSettings) {
        self.chat = chat
        self.skills = skills
        self.settings = settings
        speaker.auth = { [weak settings] in settings?.auth }
        speaker.output = recognizer
        recognizer.onText = { [weak self] in self?.heard($0) }
        recognizer.onError = { [weak self] in self?.error = $0.localizedDescription }
        recognizer.onLevel = { [weak self] in self?.micLevel = $0 }
        speaker.onFinished = { [weak self] in self?.finishedSpeaking() }
        chat.signal = { [weak self] in self?.handle($0) }
    }

    func start() async {
        guard state == .idle else { return }
        error = nil
        guard await SpeechRecognizer.requestPermissions() else {
            error = VoiceError.permissionDenied.localizedDescription
            return
        }
        do { try recognizer.start() } catch { self.error = error.localizedDescription; return }
        speaker.useServer = settings.serverVoice
        speaker.resetSession()
        transcript = ""
        muteReply = false
        state = chat.isRunning ? .thinking : .listening
        promptForPendingRequest()
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        silenceTask?.cancel()
        transcript = ""
        recognizer.nextUtterance()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        transcript = ""
        recognizer.nextUtterance()
        if state == .listening || state == .thinking { state = chat.isRunning ? .thinking : .listening }
    }

    func stop() {
        isPaused = false
        restoreModel()
        silenceTask?.cancel()
        workingCueTask?.cancel()
        speaker.stop()
        recognizer.stop()
        splitter = SpeechSentenceSplitter()
        transcript = ""
        answering = .none
        state = .idle
    }

    // MARK: Listening

    private func heard(_ text: String) {
        guard !isPaused else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != transcript else { return }
        if speaker.isSpeaking, !speaker.isPreparing, !settings.voiceBargeIn {
            return // mic ignored while Hermes talks; the utterance is reset when it finishes
        }
        if isEcho(trimmed) { return }
        transcript = trimmed
        if state == .speaking, !speaker.isPreparing, Self.wordCount(trimmed) >= 2 {
            // Barge-in: stop talking at once and drop the rest of this reply.
            speaker.stop()
            splitter = SpeechSentenceSplitter()
            muteReply = true
            interruptedLastReply = true
            state = .listening
        }
        silenceTask?.cancel()
        let pause = endOfUtterance
        silenceTask = Task { [weak self, unfinishedGrace] in
            try? await Task.sleep(for: pause)
            var extensions = 0
            while !Task.isCancelled, let self, extensions < 2, Self.soundsUnfinished(self.transcript) {
                extensions += 1
                try? await Task.sleep(for: unfinishedGrace)
            }
            guard !Task.isCancelled else { return }
            self?.utteranceEnded()
        }
    }

    private func utteranceEnded() {
        let text = transcript
        transcript = ""
        recognizer.nextUtterance()
        guard !text.isEmpty, !isEcho(text) else { return }
        if speaker.isSpeaking {
            // Anything said while Hermes talks ends the reply, even a single word.
            speaker.stop()
            splitter = SpeechSentenceSplitter()
            muteReply = true
            interruptedLastReply = true
            finishedSpeaking()
            if Self.isStopWord(text) { return }
        }
        switch answering {
        case .approval: answerApproval(text)
        case .clarify: answerClarify(text)
        case .none: Task { await submit(text) }
        }
    }

    private static let stopWords: Set<String> = ["stop", "cancel", "nevermind", "never mind", "halt"]

    private func submit(_ text: String) async {
        if Self.isStopWord(text) {
            if chat.isRunning { await chat.stop() }
            return
        }
        if chat.isRunning {
            // A stray word while Hermes works is noise, not a redirection.
            guard Self.wordCount(text) >= 2 else { return }
        }
        muteReply = false
        splitter = SpeechSentenceSplitter()
        state = .thinking
        scheduleWorkingCue()
        let turn = ChatStore.VoiceTurn(context: chat.recentExchange(), interrupted: interruptedLastReply)
        interruptedLastReply = false
        if !chat.isRunning { await applyFastModelIfNeeded() }
        if chat.isRunning {
            // Add to what Hermes is doing rather than cutting it off; 'stop' is the way to interrupt.
            if await chat.steer(text, viaVoice: true) == false {
                await chat.enqueue(text, voice: turn)
            }
        } else {
            await chat.send(text, skills: skills, voice: turn)
        }
        if chat.error != nil, state == .thinking { state = .listening }
    }

    // MARK: Fast model while talking

    private func applyFastModelIfNeeded() async {
        guard settings.voiceFastModel else { return }
        await chat.ensureSession()
        guard let sid = chat.session?.liveId, fastAppliedTo != sid else { return }
        restoreTo = chat.currentInfo
        fastAppliedTo = sid
        let alias = settings.voiceModelAlias.trimmingCharacters(in: .whitespaces)
        if !alias.isEmpty { _ = await chat.setSessionConfig("model", alias) }
        _ = await chat.setSessionConfig("reasoning", "low")
    }

    private func restoreModel() {
        guard let sid = fastAppliedTo else { return }
        fastAppliedTo = nil
        guard chat.session?.liveId == sid else { return }
        let previous = restoreTo
        restoreTo = nil
        let switchedModel = !settings.voiceModelAlias.trimmingCharacters(in: .whitespaces).isEmpty
        // Nothing recorded (session.info had not arrived yet) means the configured default, medium.
        let effort = previous.map(\.effort).flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "medium"
        Task {
            if switchedModel, let m = previous?.model, !m.isEmpty { _ = await chat.setSessionConfig("model", m) }
            _ = await chat.setSessionConfig("reasoning", effort)
        }
    }

    /// A short spoken cue when a turn runs long with nothing said yet: once at 15 s, since
    /// a normal turn produces its first words well before that.
    private func scheduleWorkingCue() {
        workingCueTask?.cancel()
        workingCueTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.state == .thinking, !self.splitter.receivedAny else { return }
            self.say("Still working on it.")
        }
    }

    // MARK: Replies

    private func handle(_ s: ChatSignal) {
        guard isActive else { return }
        switch s {
        case .turnStarted:
            muteReply = false
            if state == .listening { state = .thinking }
        case .assistantDelta(let text):
            guard !muteReply else { return }
            workingCueTask?.cancel()
            for chunk in splitter.push(text) { say(chunk) }
        case .turnComplete(let final, let status):
            workingCueTask?.cancel()
            if !muteReply {
                if !splitter.receivedAny, let final, status != "interrupted" { _ = splitter.push(final) }
                for chunk in splitter.flush() { say(chunk) }
            }
            splitter = SpeechSentenceSplitter()
            if !speaker.isSpeaking, state == .thinking { state = .listening }
        case .requestsChanged:
            promptForPendingRequest()
        }
    }

    private func say(_ text: String) {
        state = .speaking
        recentlySpoken.append((Date(), Set(Self.words(text))))
        speaker.speak(text)
    }

    /// True when most of the words were spoken by the phone in the last 20 seconds: its own
    /// voice coming back through the microphone rather than the person.
    private func isEcho(_ text: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-20)
        recentlySpoken.removeAll { $0.at < cutoff }
        let heard = Self.words(text)
        guard !heard.isEmpty, !recentlySpoken.isEmpty else { return false }
        let spoken = recentlySpoken.reduce(into: Set<String>()) { $0.formUnion($1.words) }
        let overlap = heard.filter { spoken.contains($0) }.count
        return Double(overlap) / Double(heard.count) >= 0.6
    }

    /// Why the server voice was not used this session, if it failed.
    var serverVoiceError: String? { speaker.lastError }
    /// Speaking, but the audio has not arrived from the server yet.
    var isPreparingVoice: Bool { state == .speaking && speaker.isPreparing }

    private func finishedSpeaking() {
        guard state == .speaking else { return }
        if !settings.voiceBargeIn {
            // Drop whatever the mic picked up while the phone was talking.
            silenceTask?.cancel()
            transcript = ""
            recognizer.nextUtterance()
        }
        state = chat.isRunning ? .thinking : .listening
    }

    // MARK: Permission and clarify requests by voice

    private static let spokenChoice = ["once": "allow", "session": "allow for this session", "always": "always allow", "deny": "deny"]
    private static let allowWords: Set<String> = ["allow", "yes", "ok", "okay", "approve", "sure", "yep", "yeah", "go", "proceed", "confirm"]
    private static let denyWords: Set<String> = ["deny", "no", "don't", "dont", "stop", "cancel", "reject", "nope"]

    private func promptForPendingRequest() {
        if let a = chat.pendingApproval {
            answering = .approval
            let what = !a.description.isEmpty ? a.description : (!a.command.isEmpty ? a.command : (a.toolName ?? "a command"))
            let choices = a.choices.compactMap { Self.spokenChoice[$0] }.joined(separator: ", ")
            say("Hermes needs permission to run \(SpeechText.brief(what)). Say \(choices).")
        } else if let c = chat.pendingClarify {
            answering = .clarify
            var q = c.question
            if !c.choices.isEmpty { q += ". The options are: " + c.choices.joined(separator: ", ") + "." }
            say(SpeechText.brief(q, limit: 400))
        } else if answering != .none {
            // Answered on screen while we were still asking.
            answering = .none
            if state == .speaking { speaker.stop(); finishedSpeaking() }
        }
    }

    private func answerApproval(_ spoken: String) {
        guard let a = chat.pendingApproval else { answering = .none; return }
        let words = Set(Self.words(spoken))
        let allow = !words.isDisjoint(with: Self.allowWords)
        let deny = !words.isDisjoint(with: Self.denyWords)
        var choice: String?
        if words.contains("always"), a.choices.contains("always") { choice = "always" }
        else if words.contains("session"), a.choices.contains("session") { choice = "session" }
        else if deny && !allow { choice = "deny" }
        else if allow && !deny { choice = a.choices.contains("once") ? "once" : a.choices.first }
        guard let choice else {
            say("I didn't catch that. Say \(a.choices.compactMap { Self.spokenChoice[$0] }.joined(separator: ", ")).")
            return
        }
        answering = .none
        chat.respond(to: a, choice: choice)
        say(choice == "deny" ? "Denied." : "Allowed.")
    }

    private func answerClarify(_ spoken: String) {
        guard let c = chat.pendingClarify else { answering = .none; return }
        var answer = spoken
        if !c.choices.isEmpty {
            let s = spoken.lowercased()
            let hits = c.choices.filter { let o = $0.lowercased(); return s.contains(o) || o.contains(s) }
            guard hits.count == 1 else {
                say("Which one: " + c.choices.joined(separator: ", ") + "?")
                return
            }
            answer = hits[0]
        }
        answering = .none
        chat.respond(to: c, answer: answer)
        state = .thinking
    }

    /// A sentence that trails off on a connective or a comma is probably still being spoken.
    private static func soundsUnfinished(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix(",") || t.hasSuffix("…") || t.hasSuffix("-") { return true }
        guard let last = words(t).last else { return false }
        return trailingConnectives.contains(last)
    }

    private static func isStopWord(_ s: String) -> Bool {
        stopWords.contains(words(s).joined(separator: " "))
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    private static func wordCount(_ s: String) -> Int { words(s).count }
}
