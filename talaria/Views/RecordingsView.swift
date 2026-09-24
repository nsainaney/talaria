import SwiftUI

/// All kept recordings: send or resend to Speakr, delete, and see what was sent when.
struct RecordingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let library = RecordingLibrary.shared
    private let recorder = BackgroundRecorder.shared

    var body: some View {
        NavigationStack {
            List {
                if library.items.isEmpty {
                    ContentUnavailableView("No recordings", systemImage: "mic.slash",
                                           description: Text("Recordings you make with the widget or the mic button appear here."))
                }
                ForEach(library.items) { item in
                    row(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            if canSend(item) {
                                Button { send(item) } label: {
                                    Label(item.isSent ? "Resend" : "Send", systemImage: "icloud.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Text("Recordings are deleted automatically after 30 days.")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .refreshable { library.refresh(keeping: recorder.state.fileName) }
            .task { library.refresh(keeping: recorder.state.isActive ? recorder.state.fileName : nil) }
        }
    }

    private func canSend(_ item: RecordingLibrary.Item) -> Bool {
        model.settings.speakr != nil && !item.sending && !(recorder.state.isActive && recorder.state.fileName == item.name)
    }

    private func send(_ item: RecordingLibrary.Item) {
        guard let client = model.settings.speakr else { return }
        library.send(item, client: client)
    }

    private func row(_ item: RecordingLibrary.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.sending ? "icloud.and.arrow.up" : (item.isSent ? "checkmark.circle.fill" : "circle.dashed"))
                .foregroundStyle(item.sending ? .blue : (item.isSent ? .green : .secondary))
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let d = item.duration { Text(RecordingState.stamp(d)).monospacedDigit() }
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(status(item)).font(.caption).foregroundStyle(item.error == nil ? Color.secondary : Color.red).lineLimit(2)
            }
            Spacer()
            if item.sending {
                ProgressView()
            } else if let id = item.sentId, let client = model.settings.speakr {
                Link(destination: client.pageURL(id: id)) { Image(systemName: "arrow.up.right.square") }
            } else if canSend(item) {
                Button { send(item) } label: { Image(systemName: "icloud.and.arrow.up") }
            }
        }
        .buttonStyle(.borderless)
        .contextMenu {
            if canSend(item) {
                Button { send(item) } label: { Label(item.isSent ? "Resend to Speakr" : "Send to Speakr", systemImage: "icloud.and.arrow.up") }
            }
            ShareLink(item: item.url) { Label("Share audio", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func status(_ item: RecordingLibrary.Item) -> String {
        if recorder.state.isActive, recorder.state.fileName == item.name { return "Recording now" }
        if item.sending { return "Sending to Speakr…" }
        if let e = item.error { return "Not sent: \(e)" }
        if let id = item.sentId, let at = item.sentAt {
            return "Sent to Speakr as #\(id) · \(at.formatted(.relative(presentation: .named)))"
        }
        return "Not sent"
    }
}
