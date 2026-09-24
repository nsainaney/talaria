import SwiftUI

enum InboxFilter: String, CaseIterable {
    case all = "All", chats = "Chats", recordings = "Recordings"
}

enum InboxDestination: Hashable {
    case chat(HermesSession)
    case newChat(voice: Bool)
}

/// The root: one list of chats and recordings, newest first, with what is still going on at the top.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    @State private var query = ""
    @State private var filter: InboxFilter = .all
    @State private var expanded: String?
    @State private var showSettings = false
    private let library = RecordingLibrary.shared
    private let recorder = BackgroundRecorder.shared

    enum Entry: Identifiable {
        case chat(HermesSession)
        case recording(RecordingLibrary.Item)
        var id: String {
            switch self {
            case .chat(let s): return "s:" + s.id
            case .recording(let r): return "r:" + r.name
            }
        }
        var date: Date {
            switch self {
            case .chat(let s): return s.startedDate ?? .distantPast
            case .recording(let r): return r.date
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(GlassBackground())
        .safeAreaInset(edge: .bottom) { footer }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await model.connect() } }) { SettingsView() }
        .task { library.refresh(keeping: recorder.state.fileName) }
        .onChange(of: recorder.state.phase) { _, _ in library.refresh(keeping: recorder.state.fileName) }
        .onChange(of: expanded) { _, name in if name == nil { PlaybackPlayer.shared.stop() } }
    }

    // MARK: Header: search, settings, filter

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .glass(Theme.small)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.body.weight(.medium)).frame(width: 38, height: 38)
            }
            .glass(Theme.small)
            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(InboxFilter.allCases, id: \.self) { f in
                        Label(f.rawValue, systemImage: f == .all ? "tray" : f == .chats ? "sparkles" : "mic.fill").tag(f)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.accent)
                    Text(filter.rawValue).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 11).frame(height: 38)
            }
            .glass(Theme.small)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
    }

    // MARK: Entries and grouping

    private var entries: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [Entry] = []
        if filter != .recordings {
            out += model.sessions.filter {
                q.isEmpty || $0.displayTitle.lowercased().contains(q) || ($0.preview ?? "").lowercased().contains(q)
            }.map(Entry.chat)
        }
        if filter != .chats {
            out += library.items.filter { q.isEmpty || $0.displayTitle.lowercased().contains(q) }.map(Entry.recording)
        }
        return out.sorted { $0.date > $1.date }
    }

    private func isActive(_ e: Entry) -> Bool {
        switch e {
        case .chat(let s): return model.chat.isRunning(s)
        case .recording(let r): return recorder.state.isActive && recorder.state.fileName == r.name
        }
    }

    private func isPinned(_ e: Entry) -> Bool {
        if case .chat(let s) = e { return model.pins.isSessionPinned(s.id) }
        return false
    }

    private var sections: [(title: String, rows: [Entry])] {
        let all = entries
        var out: [(String, [Entry])] = []
        let active = all.filter(isActive)
        if !active.isEmpty { out.append(("Active", active)) }
        let pinned = all.filter { isPinned($0) && !isActive($0) }
        if !pinned.isEmpty { out.append(("Pinned", pinned)) }
        let rest = all.filter { !isActive($0) && !isPinned($0) }
        let cal = Calendar.current
        var byDay: [(String, [Entry])] = []
        for e in rest {
            let label = Self.dayLabel(e.date, cal)
            if let i = byDay.firstIndex(where: { $0.0 == label }) { byDay[i].1.append(e) } else { byDay.append((label, [e])) }
        }
        return out + byDay
    }

    private static func dayLabel(_ d: Date, _ cal: Calendar) -> String {
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let week = cal.date(byAdding: .day, value: -6, to: Date()), d > week { return d.formatted(.dateTime.weekday(.wide)) }
        if d == .distantPast { return "Earlier" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    private static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if let week = cal.date(byAdding: .day, value: -6, to: Date()), d > week { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: List

    private var list: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Nothing yet" : "No matches", systemImage: query.isEmpty ? "tray" : "magnifyingglass",
                                       description: Text(query.isEmpty ? "Start a chat or a recording below." : "Try another search."))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.rows) { e in
                        row(e)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    }
                } header: {
                    Text(section.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase).padding(.leading, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await model.refreshSessions()
            library.refresh(keeping: recorder.state.fileName)
        }
        .overlay { if model.isLoadingSessions && model.sessions.isEmpty { ProgressView() } }
    }

    @ViewBuilder private func row(_ e: Entry) -> some View {
        switch e {
        case .chat(let s): chatRow(s, active: isActive(e))
        case .recording(let r): recordingRow(r, live: isActive(e))
        }
    }

    private func chatRow(_ s: HermesSession, active: Bool) -> some View {
        Button { path.append(InboxDestination.chat(s)) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: "sparkles", color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                    if let p = s.preview, !p.isEmpty, let t = s.title, !t.isEmpty {
                        Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if active {
                    StatusBadge(text: "running", color: Theme.accent)
                } else if let d = s.startedDate {
                    Text(Self.when(d)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(active ? Theme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.small, style: .continuous))
        .glass(Theme.small)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await model.delete(s) } } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { model.pins.toggleSession(s.id) } label: {
                Label(model.pins.isSessionPinned(s.id) ? "Unpin" : "Pin", systemImage: model.pins.isSessionPinned(s.id) ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { model.pins.toggleSession(s.id) } label: {
                Label(model.pins.isSessionPinned(s.id) ? "Unpin" : "Pin", systemImage: model.pins.isSessionPinned(s.id) ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { Task { await model.delete(s) } } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func recordingRow(_ r: RecordingLibrary.Item, live: Bool) -> some View {
        let open = expanded == r.name
        return VStack(spacing: 0) {
            Button {
                if live { model.showRecorder = true } else { withAnimation(.snappy) { expanded = open ? nil : r.name } }
            } label: {
                HStack(spacing: 10) {
                    IconBadge(symbol: "mic.fill", color: Theme.rec, filled: live)
                    VStack(alignment: .leading, spacing: 2) {
                        if open {
                            InlineTitleField(text: r.displayTitle) { library.rename(r.name, to: $0) }
                        } else {
                            Text(r.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                        }
                        Text(subtitle(r, live: live)).font(.caption).foregroundStyle(r.error == nil ? .secondary : Theme.rec).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if live {
                        StatusBadge(text: "live", color: Theme.rec)
                    } else if open {
                        Menu {
                            ShareLink(item: r.url) { Label("Share audio", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { library.delete(r) } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Theme.accent).frame(width: 28, height: 28)
                        }
                    } else {
                        Text(Self.when(r.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                RecordingInlineView(item: r).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(live ? Theme.rec.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.small, style: .continuous))
        .glass(Theme.small)
        .swipeActions(edge: .trailing) {
            if !live {
                Button(role: .destructive) { library.delete(r) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func subtitle(_ r: RecordingLibrary.Item, live: Bool) -> String {
        if live { return "Recording now" }
        var parts: [String] = []
        if let d = r.duration { parts.append(RecordingState.stamp(d)) }
        if r.sending { parts.append("Sending to Speakr…") }
        else if let e = r.error { parts.append("Not sent: \(e)") }
        else if let id = r.sentId { parts.append("Sent to Speakr as #\(id)") }
        else { parts.append("Not sent") }
        return parts.joined(separator: " · ")
    }

    // MARK: Footer: Chat · Voice chat · Record

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Chat", "pencil", Theme.accent) { path.append(InboxDestination.newChat(voice: false)) }
            footerButton("Voice chat", "waveform", Theme.accent) { path.append(InboxDestination.newChat(voice: true)) }
            footerButton("Record", "mic.fill", Theme.rec) { Task { try? await recorder.start() } }
                .disabled(recorder.state.isActive)
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 6)
    }

    private func footerButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(Theme.small)
    }
}

/// A title that is edited where it is shown: tap, type, return.
struct InlineTitleField: View {
    let text: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Title", text: $draft)
            .font(.body.weight(.medium))
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { commit(draft.trimmingCharacters(in: .whitespaces)) }
            .onAppear { draft = text }
            .onChange(of: focused) { was, now in if was && !now { commit(draft.trimmingCharacters(in: .whitespaces)) } }
    }
}
