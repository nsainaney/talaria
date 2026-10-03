import SwiftUI

/// The expanded part of a recording row: scrubber, then send · skip back · play · skip forward · delete.
struct RecordingInlineView: View {
    @Environment(AppModel.self) private var model
    let item: RecordingLibrary.Item
    private let player = PlaybackPlayer.shared
    private let library = RecordingLibrary.shared
    @State private var confirmResend = false

    var body: some View {
        let current = player.playingName == item.name
        let duration = current && player.duration > 0 ? player.duration : (item.duration ?? 0)
        let position = current ? player.position : 0
        VStack(spacing: 6) {
            Slider(value: Binding(get: { duration > 0 ? position / duration : 0 },
                                  set: { f in if current { player.seek(to: f) } else { player.toggle(item.url); player.seek(to: f) } }))
                .tint(Theme.accent)
            HStack {
                Text(RecordingState.stamp(position))
                Spacer()
                Text("−" + RecordingState.stamp(max(0, duration - position)))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .padding(.top, -6)
            HStack {
                sendButton
                Spacer()
                Button { player.skip(-15, in: item.url) } label: { Image(systemName: "gobackward.15") }
                Spacer()
                Button { player.toggle(item.url) } label: {
                    Image(systemName: current && player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button { player.skip(15, in: item.url) } label: { Image(systemName: "goforward.15") }
                Spacer()
                Button(role: .destructive) { library.delete(item) } label: { Image(systemName: "trash").foregroundStyle(Theme.rec) }
            }
            .font(.title2)
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            if let e = player.error, current { Text(e).font(.caption2).foregroundStyle(Theme.rec) }
        }
        .confirmationDialog("Send to Speakr again?", isPresented: $confirmResend, titleVisibility: .visible) {
            Button("Send again") { send() }
        } message: {
            Text("It is already there as recording #\(item.sentId ?? 0). Sending again creates a second copy.")
        }
    }

    @ViewBuilder private var sendButton: some View {
        if item.sending {
            ProgressView().frame(width: 28, height: 28)
        } else if model.settings.speakr == nil {
            Image(systemName: "icloud.slash").foregroundStyle(.tertiary)
        } else if item.isSent {
            Button { confirmResend = true } label: { Image(systemName: "arrow.clockwise.icloud").foregroundStyle(.secondary) }
                .accessibilityLabel("Send to Speakr again")
        } else {
            Button { send() } label: { Image(systemName: "icloud.and.arrow.up").foregroundStyle(Theme.accent) }
                .accessibilityLabel("Send to Speakr")
        }
    }

    private func send() {
        guard let client = model.settings.speakr else { return }
        library.send(item, client: client)
    }
}
