import SwiftUI

struct SessionsSidebar: View {
    @Environment(AppModel.self) private var model
    /// nil means "start a new chat".
    let onSelect: (HermesSession?) -> Void

    @State private var query = ""
    @State private var renaming: HermesSession?
    @State private var renameText = ""

    private var visible: [HermesSession] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = q.isEmpty ? model.sessions : model.sessions.filter {
            $0.displayTitle.lowercased().contains(q) || ($0.preview ?? "").lowercased().contains(q)
        }
        // Pinned first, then by recency as the server returned them.
        return rows.filter { model.pins.isSessionPinned($0.id) } + rows.filter { !model.pins.isSessionPinned($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions").font(.title2.bold())
                Spacer()
                Button { Task { await model.refreshSessions() } } label: { Image(systemName: "arrow.clockwise") }
            }
            .padding()
            Button { onSelect(nil) } label: {
                Label("New chat", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            TextField("Search sessions", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal).padding(.top, 8)
            if let err = model.sessionsError {
                Text(err).font(.footnote).foregroundStyle(.red).padding()
            }
            List {
                ForEach(visible) { s in
                    row(s)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay { if model.isLoadingSessions && model.sessions.isEmpty { ProgressView() } }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert("Rename session", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let s = renaming { Task { await model.rename(s, to: renameText) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ s: HermesSession) -> some View {
        Button { onSelect(s) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if model.pins.isSessionPinned(s.id) { Image(systemName: "pin.fill").font(.caption2) }
                    Text(s.displayTitle).lineLimit(1)
                }
                .foregroundStyle(.primary)
                if let d = s.startedDate {
                    Text(d, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(model.chat.session?.id == s.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contextMenu {
            Button { beginRename(s) } label: { Label("Rename", systemImage: "pencil") }
            Button { model.pins.toggleSession(s.id) } label: {
                Label(model.pins.isSessionPinned(s.id) ? "Unpin" : "Pin", systemImage: model.pins.isSessionPinned(s.id) ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { Task { await model.delete(s) } } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await model.delete(s) } } label: { Label("Delete", systemImage: "trash") }
            Button { beginRename(s) } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button { model.pins.toggleSession(s.id) } label: {
                Label(model.pins.isSessionPinned(s.id) ? "Unpin" : "Pin", systemImage: model.pins.isSessionPinned(s.id) ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    private func beginRename(_ s: HermesSession) {
        renameText = s.title ?? ""
        renaming = s
    }
}
