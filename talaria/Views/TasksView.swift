import SwiftUI

/// Two lists. Triage: what came in, then the Hermes backlog. In progress: what Hermes is doing,
/// then Done for the week. The magnifier scans; the system screens each item once.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    @State private var segment: Segment = .triage
    @State private var remindFor: TriageEntry?
    @State private var ignored: TriageEntry?
    @State private var busy: Set<String> = []
    /// Source filter on the New section; "" is all. Kept across launches.
    @AppStorage("tasks.sourceFilter") private var sourceFilter = ""
    /// Drag handles on the New section.
    @State private var reordering = false

    enum Segment: String, CaseIterable { case triage = "Triage", progress = "In progress" }

    private var tasks: TasksStore { model.tasks }

    var body: some View {
        VStack(spacing: 0) {
            picker
            if let err = tasks.error {
                Text(err).font(.footnote).foregroundStyle(.red).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 6)
            }
            if segment == .triage { triage } else { progress }
        }
        .background(GlassBackground())
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if segment == .triage, tasks.new.count > 1 {
                    Button(reordering ? "Done" : "Reorder") { withAnimation { reordering.toggle() } }
                        .font(reordering ? .body.weight(.semibold) : .body)
                }
                Button { Task { await tasks.scan() } } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .disabled(tasks.context == nil || tasks.scanning != nil)
                .accessibilityLabel("Scan for things to triage")
            }
        }
        .task {
            await tasks.refresh()
            tasks.startLive()
        }
        .onDisappear { tasks.stopLive() }
        .sheet(item: $remindFor) { entry in
            RemindSheet(entry: entry) { day, time, list in
                await answer(entry.id) { try await tasks.remind(entry, day: day, time: time, listId: list) }
            }
            .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) { ignoredToast }
    }

    private var picker: some View {
        Picker("", selection: $segment) {
            ForEach(Segment.allCases, id: \.self) { s in
                Text(label(for: s)).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
    }

    private func label(for s: Segment) -> String {
        switch s {
        case .triage: return tasks.triageCount > 0 ? "Triage · \(tasks.triageCount)" : "Triage"
        case .progress:
            let n = tasks.inProgress.count
            return n > 0 ? "In progress · \(n)" : "In progress"
        }
    }

    // MARK: Triage

    private var triage: some View {
        List {
            if let s = tasks.scanning { scanRow(s).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(rowInsets) }
            if tasks.new.isEmpty && tasks.backlog.isEmpty && !tasks.isLoading {
                ContentUnavailableView(tasks.context == nil ? "Not signed in" : "Nothing to triage",
                                       systemImage: "tray",
                                       description: Text(tasks.context == nil ? "Sign in to the dashboard in Settings to see what came in." :
                                                            (tasks.asOf.map { "Nothing new since " + Self.when($0) + ". Scan to look again." } ?? "Scan to look at what arrived.")))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if !tasks.new.isEmpty {
                Section {
                    if sourceCounts.count > 1 {
                        sourceChips.listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                    }
                    ForEach(filteredNew) { e in
                        newRow(e).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(rowInsets)
                    }
                    .onMove { from, to in Task { await dragged(from: from, to: to) } }
                } header: { header("New", filteredNew.count) }
            }
            if !tasks.backlog.isEmpty {
                Section {
                    ForEach(tasks.backlog) { c in
                        backlogRow(c).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(rowInsets)
                    }
                } header: { header("Hermes backlog", tasks.backlog.count) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .refreshable { await tasks.refresh() }
        .overlay { if tasks.isLoading && tasks.new.isEmpty && tasks.backlog.isEmpty { ProgressView() } }
        .onChange(of: segment) { _, _ in reordering = false }
    }

    /// A drag in the New section: the moved row lands before its new lower neighbour, or after
    /// the last row. With a source filter on, the anchor is still a real neighbour in the store's order.
    private func dragged(from: IndexSet, to: Int) async {
        var arr = filteredNew
        guard let src = from.first, src < arr.count else { return }
        let moved = arr[src]
        arr.move(fromOffsets: from, toOffset: to)
        guard let i = arr.firstIndex(where: { $0.id == moved.id }) else { return }
        if i + 1 < arr.count {
            await answer(moved.id) { try await tasks.move(moved, "before", anchor: arr[i + 1]) }
        } else if i > 0 {
            await answer(moved.id) { try await tasks.move(moved, "after", anchor: arr[i - 1]) }
        }
    }

    private func newRow(_ e: TriageEntry) -> some View {
        Button { path.append(InboxDestination.taskItem(e)) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: e.item.symbol, color: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle(e)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if busy.contains(e.id) { ProgressView().controlSize(.small) }
                else { Text(Self.when(e.item.ts)).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(Theme.small)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            answerButton(.me, e)
            answerButton(.done, e)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            answerButton(.ignore, e)
            answerButton(.agent, e)
        }
        .contextMenu {
            ForEach(TriageAnswer.allCases) { a in answerButton(a, e) }
            Divider()
            ForEach(MoveAction.allCases) { m in moveButton(m, e) }
        }
    }

    /// Sources present in New, in a fixed order, with counts.
    private var sourceCounts: [(source: String, count: Int)] {
        let order = ["office365", "google", "imessage", "speakr", "github", "manual", "kanban"]
        var counts: [String: Int] = [:]
        for e in tasks.new { counts[e.item.source, default: 0] += 1 }
        return counts.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }.map { ($0, counts[$0]!) }
    }

    private var filteredNew: [TriageEntry] {
        guard !sourceFilter.isEmpty, sourceCounts.contains(where: { $0.source == sourceFilter }) else { return tasks.new }
        return tasks.new.filter { $0.item.source == sourceFilter }
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", tasks.new.count, on: sourceFilter.isEmpty || !sourceCounts.contains { $0.source == sourceFilter }) { sourceFilter = "" }
                ForEach(sourceCounts, id: \.source) { sc in
                    chip(Self.sourceName(sc.source), sc.count, on: sourceFilter == sc.source) { sourceFilter = sc.source }
                }
            }
        }
    }

    private func chip(_ title: String, _ n: Int, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 5) {
                Text(title)
                Text("\(n)").fontWeight(.regular).opacity(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(on ? Theme.accent : Color.clear, in: Capsule())
            .glass(999)
        }
        .buttonStyle(.plain)
    }

    /// The same answer, the same glyph and tint, in a swipe or a menu.
    private func answerButton(_ a: TriageAnswer, _ e: TriageEntry) -> some View {
        Button {
            switch a {
            case .me: remindFor = e
            case .agent: Task { await answer(e.id) { try await tasks.agent(e) } }
            case .done: Task { await answer(e.id) { try await tasks.markDone(e) } }
            case .ignore: Task { await ignore(e) }
            }
        } label: { a.label }
        .tint(a.tint)
    }

    private func moveButton(_ m: MoveAction, _ e: TriageEntry) -> some View {
        Button { Task { await answer(e.id) { try await tasks.move(e, to: m.rawValue) } } } label: { m.label }
    }

    private func subtitle(_ e: TriageEntry) -> String {
        var parts = [e.item.sourceLine]
        if let c = e.candidate, let d = c.suggestedDue { parts.append("by " + d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
        return parts.joined(separator: " · ")
    }

    private func backlogRow(_ c: KanbanCard) -> some View {
        Button { path.append(InboxDestination.taskCard(c)) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: c.status == "todo" ? "clock" : "cpu", color: c.status == "todo" ? .secondary : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(backlogSubtitle(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if busy.contains(c.id) { ProgressView().controlSize(.small) }
                else if c.status == "ready" { StatusBadge(text: "starting", color: Theme.accent) }
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(Theme.small)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            ForEach(CardAction.available(for: c).filter { $0 != .drop }) { a in cardButton(a, c) }
        }
        .swipeActions(edge: .trailing) {
            if CardAction.available(for: c).contains(.drop) { cardButton(.drop, c) }
        }
        .contextMenu {
            ForEach(CardAction.available(for: c)) { a in cardButton(a, c) }
        }
    }

    private func cardButton(_ a: CardAction, _ c: KanbanCard) -> some View {
        Button(role: a == .drop ? .destructive : nil) {
            switch a {
            case .start: Task { await startChat(c) }
            case .release: Task { await answer(c.id) { try await tasks.start(c) } }
            case .stop: Task { await answer(c.id) { try await tasks.stop(c) } }
            case .drop: Task { await answer(c.id) { try await tasks.drop(c) } }
            }
        } label: { a.label }
        .tint(a.tint)
    }

    private func backlogSubtitle(_ c: KanbanCard) -> String {
        var parts: [String] = []
        if let a = c.assignee { parts.append(a) }
        switch c.status {
        case "todo": parts.append(c.parentCount > 0 ? "after another card · starts by itself" : "waiting")
        case "scheduled": parts.append("held")
        default: parts.append("not started")
        }
        return parts.joined(separator: " · ")
    }

    private func scanRow(_ s: ContextClient.Scanning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning").font(.subheadline.weight(.semibold))
                Spacer()
                Text(s.total > 0 ? "\(s.done) of \(s.total)" : "starting").font(.caption).foregroundStyle(.secondary)
            }
            if s.total > 0 { ProgressView(value: Double(s.done), total: Double(max(s.total, 1))).tint(Theme.accent) }
            HStack {
                Text(s.found == 1 ? "1 candidate so far" : "\(s.found) candidates so far").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if s.skipped > 0 { Text("\(s.skipped) deferred" + (s.skippedReason.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.orange) }
            }
            if !s.bySource.isEmpty {
                Text(s.bySource.map { "\(Self.sourceName($0.source)) \($0.done) of \($0.total)" + ($0.found > 0 ? " · \($0.found) found" : "") }.joined(separator: "   "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(12).glass(Theme.small)
    }

    // MARK: In progress

    private var progress: some View {
        List {
            if tasks.inProgress.isEmpty && tasks.done.isEmpty && !tasks.isLoading {
                ContentUnavailableView("Hermes is idle", systemImage: "cpu", description: Text("Start something from the backlog and it shows up here."))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if !tasks.inProgress.isEmpty {
                Section {
                    ForEach(tasks.inProgress) { c in
                        progressRow(c).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(rowInsets)
                    }
                }
            }
            if !tasks.done.isEmpty {
                Section {
                    ForEach(tasks.done) { c in
                        doneRow(c).listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(rowInsets)
                    }
                } header: { header("Done", nil, "this week") }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await tasks.refresh() }
    }

    private func progressRow(_ c: KanbanCard) -> some View {
        Button { path.append(InboxDestination.taskCard(c)) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: c.needsYou ? "person" : "cpu", color: c.needsYou ? .orange : Theme.accent, filled: c.status == "running")
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(progressSubtitle(c)).font(.caption).foregroundStyle(c.needsYou ? .primary : .secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if c.needsYou { StatusBadge(text: "reply", color: .orange) }
                else if c.status == "running" { StatusBadge(text: "live", color: Theme.accent) }
                else if c.status == "ready" { Text("starting").font(.caption).foregroundStyle(.secondary) }
                else if c.status == "blocked" { StatusBadge(text: c.blockKind ?? "blocked", color: .orange) }
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(c.status == "running" ? Theme.accent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.small, style: .continuous))
        .glass(Theme.small)
        .swipeActions(edge: .trailing) {
            ForEach(CardAction.available(for: c)) { a in cardButton(a, c) }
        }
        .contextMenu {
            ForEach(CardAction.available(for: c)) { a in cardButton(a, c) }
        }
    }

    private func progressSubtitle(_ c: KanbanCard) -> String {
        var parts: [String] = []
        if let a = c.assignee { parts.append(a) }
        if c.needsYou, let q = c.latestSummary ?? c.lastError, !q.isEmpty { parts.append(q) }
        else if let s = c.startedAt, c.status == "running" { parts.append(Self.elapsed(since: s)) }
        if let w = c.workspace, c.status == "running" { parts.append(URL(fileURLWithPath: w).lastPathComponent) }
        return parts.joined(separator: " · ")
    }

    private func doneRow(_ c: KanbanCard) -> some View {
        Button { path.append(InboxDestination.taskCard(c)) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: c.lastError == nil ? "checkmark" : "xmark", color: c.lastError == nil ? .green : Theme.rec)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.body.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Text([c.assignee, c.latestSummary].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let d = c.completedAt { Text(Self.when(d)).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(Theme.small)
    }

    // MARK: Actions

    private func answer(_ id: String, _ work: @escaping () async throws -> Void) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do { try await work() } catch { tasks.error = error.localizedDescription }
    }

    private func ignore(_ e: TriageEntry) async {
        await answer(e.id) { try await tasks.ignore(e) }
        withAnimation { ignored = e }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if ignored?.id == e.id { withAnimation { ignored = nil } }
        }
    }

    /// Start: a chat that enriches the card with the task-grill skill, then Proceed in that chat.
    private func startChat(_ c: KanbanCard) async {
        busy.insert(c.id)
        defer { busy.remove(c.id) }
        let msg = TasksStore.startMessage(for: c, hasSkill: model.skills.skill(named: "task-grill") != nil)
        if let s = await model.startChat(msg.text, file: msg.file, title: c.title) {
            tasks.rememberSession(s.id, for: c.id)
            try? await model.settings.auth?.kanbanComment(c.id, board: c.board.isEmpty ? nil : c.board, "Discussed in talaria://chat/\(s.id)")
            path.append(InboxDestination.chat(s))
        }
    }

    @ViewBuilder private var ignoredToast: some View {
        if let e = ignored {
            HStack(spacing: 10) {
                Image(systemName: "xmark").foregroundStyle(.secondary)
                Text("Ignored").font(.subheadline)
                Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button("Why?") { Task { await why(e) } }.font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glass(Theme.small)
            .padding(.horizontal, 16).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func why(_ e: TriageEntry) async {
        ignored = nil
        let msg = TasksStore.whyMessage(for: e, decision: "ignore", hasSkill: model.skills.skill(named: "screener-feedback") != nil)
        if let s = await model.startChat(msg.text, file: msg.file, title: "Why ignore · " + e.title) {
            path.append(InboxDestination.chat(s))
        }
    }

    // MARK: Bits

    private var rowInsets: EdgeInsets { EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16) }

    private func header(_ title: String, _ n: Int?, _ note: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let n { Text("\(n)").fontWeight(.regular) }
            if let note { Text(note).fontWeight(.regular) }
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.leading, 4)
    }

    static func sourceName(_ s: String) -> String {
        switch s {
        case "office365", "google": return "Mail"
        case "imessage": return "iMessage"
        case "speakr": return "Meetings"
        case "github": return "GitHub"
        case "manual": return "Hermes"
        default: return s.capitalized
        }
    }

    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if let week = cal.date(byAdding: .day, value: -6, to: Date()), d > week { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    static func elapsed(since d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 90 { return "\(s) s" }
        if s < 5400 { return "\(s / 60) min" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
    }
}
