import SwiftUI

/// Record a meeting, watch the live transcript, then hand the transcript to Hermes.
struct MeetingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MeetingRecorder()
    @State private var instruction = ""
    @State private var sending = false

    static let fallbackInstruction = "Digest the attached meeting transcript: summarize it in a few sentences, list decisions and action items with owners and dates, save the durable facts to memory, and propose reminders for dated follow-ups. Ask before creating anything."

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(MeetingRecorder.stamp(recorder.elapsed))
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                    .padding(.top, 8)
                if recorder.isRecording {
                    Label("Recording · transcribed on this phone", systemImage: "record.circle")
                        .font(.footnote).foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: true)
                }
                transcript
                if let e = recorder.error {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
                controls
            }
            .padding()
            .navigationTitle("Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recorder.isRecording ? "Stop & close" : "Close") { recorder.stop(); dismiss() }
                }
            }
            .task {
                model.voice.stop()
                if instruction.isEmpty {
                    instruction = model.skills.skill(named: "meeting-digest") != nil ? "/meeting-digest" : Self.fallbackInstruction
                }
                await recorder.start()
            }
        }
        .interactiveDismissDisabled(recorder.isRecording)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(recorder.segments) { seg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(MeetingRecorder.stamp(seg.start)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(seg.text).textSelection(.enabled)
                        }
                    }
                    if !recorder.partial.isEmpty {
                        Text(recorder.partial).foregroundStyle(.secondary)
                    }
                    if recorder.segments.isEmpty && recorder.partial.isEmpty {
                        Text(recorder.isRecording ? "Listening…" : "Nothing recorded yet.")
                            .foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: recorder.partial) { _, _ in proxy.scrollTo("end") }
            .onChange(of: recorder.segments.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
        }
    }

    @ViewBuilder private var controls: some View {
        if recorder.isRecording {
            Button { recorder.stop() } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        } else if !recorder.segments.isEmpty {
            TextField("What should Hermes do with it?", text: $instruction, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
            Button { Task { await send() } } label: {
                HStack {
                    Label("Send to Hermes", systemImage: "paperplane.fill")
                    if sending { ProgressView().padding(.leading, 6) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(sending || !model.gateway.isConnected || instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            if let url = recorder.fileURL {
                Text("Audio saved to Files › Talaria › Meetings › \(url.lastPathComponent)")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else {
            Button { Task { await recorder.start() } } label: {
                Label("Start recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let name = (recorder.fileURL?.deletingPathExtension().lastPathComponent ?? "Meeting") + ".txt"
        await model.chat.send(instruction, files: [(name: name, text: recorder.transcriptText)], skills: model.skills)
        if model.chat.error == nil { dismiss() }
    }
}
