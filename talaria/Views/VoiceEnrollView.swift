import SwiftUI

/// Teach the phone the owner's voice: three sentences read aloud through the same audio path the
/// voice loop uses (voice processing on), averaged into one profile that the speaker verifier
/// compares every utterance against. Each sentence has its own record button; tap, read, tap again.
struct VoiceEnrollView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = EnrollRecorder()
    @State private var recordings: [Int: [Float]] = [:]
    @State private var recordingIndex: Int?
    @State private var result: String?
    @State private var saving = false

    private static let phrases = [
        "What came in today, and what is the first one about?",
        "Remind me tomorrow morning to look at the refund and reply to the team.",
        "Hermes, read me the last message and tell me if anything needs an answer.",
    ]

    private var complete: Bool { recordings.count == Self.phrases.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.phrases.indices, id: \.self) { i in
                        phraseRow(i)
                    }
                } header: {
                    Text("Read each sentence")
                } footer: {
                    Text("Hold the phone as you do when talking to Hermes, in a quiet moment. Tap the microphone, read the sentence, tap the stop button. Tap again to redo one.")
                }
                Section {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Label("Save my voice", systemImage: "person.wave.2") }
                    }
                    .disabled(!complete || saving || recordingIndex != nil)
                    if let e = recorder.error { Text(e).font(.footnote).foregroundStyle(Theme.rec) }
                    if let result { Text(result).font(.footnote) }
                }
                if SpeakerVerifier.hasProfile {
                    Section {
                        Button("Forget my voice", role: .destructive) {
                            Task { await SpeakerVerifier.shared.forget(); dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("My voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onDisappear { recorder.stop() }
        }
    }

    private func phraseRow(_ i: Int) -> some View {
        let active = recordingIndex == i
        let done = recordings[i] != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(Self.phrases[i])
                    .foregroundStyle(active || !done ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if active { finishRecording(i) } else { begin(i) }
                } label: {
                    Image(systemName: active ? "stop.circle.fill" : (done ? "checkmark.circle.fill" : "mic.circle.fill"))
                        .font(.title)
                        .foregroundStyle(active ? Theme.rec : (done ? .green : Theme.accent))
                        .symbolEffect(.pulse, isActive: active)
                }
                .buttonStyle(.plain)
                .disabled(recordingIndex != nil && !active)
                .accessibilityLabel(active ? "Stop" : (done ? "Record again" : "Record"))
            }
            if active {
                Text(recorder.transcript.isEmpty ? "Listening…" : recorder.transcript)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func begin(_ i: Int) {
        result = nil
        recordingIndex = i
        recorder.start()
    }

    private func finishRecording(_ i: Int) {
        recordingIndex = nil
        guard let samples = recorder.finish() else { return }
        if Double(samples.count) / 16000 < 1.5 {
            recorder.error = "That was too short; read the whole sentence."
            return
        }
        recordings[i] = samples
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let takes = Self.phrases.indices.compactMap { recordings[$0] }
            let agreement = try await SpeakerVerifier.shared.enroll(takes)
            result = agreement < 0.5
                ? String(format: "Saved, but the recordings only agree %.0f%%. Redo them somewhere quieter.", agreement * 100)
                : String(format: "Saved. Recordings agree %.0f%%.", agreement * 100)
            if agreement >= 0.5 { model.settings.voiceOnlyMine = true }
        } catch {
            result = error.localizedDescription
        }
    }
}

/// Runs the voice loop's recognizer with no listener attached, so the recording comes through the
/// same voice-processing unit, and hands back the 16 kHz audio of one take.
@Observable @MainActor
final class EnrollRecorder {
    private(set) var isRecording = false
    private(set) var transcript = ""
    var error: String?
    private let recognizer = SpeechRecognizer()
    private var startedAt: Date?

    init() {
        recognizer.onText = { [weak self] in self?.transcript = $0 }
        recognizer.onError = { [weak self] in self?.error = $0.localizedDescription }
    }

    func start() {
        error = nil
        transcript = ""
        Task {
            guard await SpeechRecognizer.requestPermissions() else { error = VoiceError.permissionDenied.localizedDescription; return }
            do { try recognizer.start() } catch { self.error = error.localizedDescription; return }
            startedAt = Date()
            isRecording = true
        }
    }

    /// The audio since the take began; the mic stays open so the next take starts at once.
    func finish() -> [Float]? {
        guard isRecording, let startedAt else { return nil }
        isRecording = false
        let samples = recognizer.recentAudio(seconds: min(20, Date().timeIntervalSince(startedAt)))
        recognizer.nextUtterance()
        return samples
    }

    func stop() {
        isRecording = false
        recognizer.stop()
    }
}
