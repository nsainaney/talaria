import SwiftUI

/// A kanban card: the body, the trail (comments and events), and what it needs now: a reply when
/// it is blocked, Start when it has not begun, Stop while it runs.
struct TaskCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Binding var path: NavigationPath
    let card: KanbanCard
    @State private var detail: KanbanCardDetail?
    @State private var reply = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var replyFocused: Bool

    private var tasks: TasksStore { model.tasks }
    private var current: KanbanCard { detail?.card ?? card }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stateLine
                    Text(current.body.isEmpty ? "No description." : current.body)
                        .font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).glass(Theme.small)
                    if !current.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(current.tags, id: \.self) { t in
                                Text("#" + t).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 9).padding(.vertical, 4).glass(999)
                            }
                        }
                    }
                    if current.needsYou, let q = current.latestSummary ?? current.lastError, !q.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Needs you").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.orange)
                            Text(q).font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if let u = current.sourceURL { linkRow("Open the source", u) }
                    if let sid = tasks.cardSessions[current.id] ?? current.sessionId, let s = session(sid) {
                        Button { path.append(InboxDestination.chat(s)) } label: {
                            HStack(spacing: 8) { Image(systemName: "sparkles"); Text("Open the chat").font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                .padding(12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).glass(Theme.small)
                    }
                    trail
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            }
            if current.needsYou { replyBar }
        }
        .background(GlassBackground())
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(CardAction.available(for: current)) { a in
                        Button(role: a == .drop ? .destructive : nil) {
                            switch a {
                            case .start: Task { await start() }
                            case .release: Task { await run { try await tasks.start(current) } }
                            case .stop: Task { await run { try await tasks.stop(current) } }
                            case .drop: Task { await run { try await tasks.drop(current) }; if !path.isEmpty { path.removeLast() } }
                            case .archive: Task { await run { try await tasks.archive(current) }; if !path.isEmpty { path.removeLast() } }
                            }
                        } label: { a.label }
                    }
                    Divider()
                    Button { UIPasteboard.general.string = current.board.isEmpty ? "talaria://task/\(current.id)" : "talaria://task/\(current.board)/\(current.id)" } label: { Label("Copy link", systemImage: "link") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .safeAreaInset(edge: .bottom) { if current.status == "triage" || current.status == "todo" { startBar } }
        .task { await load() }
        .refreshable { await load() }
    }

    private var stateLine: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            Text(stateText).font(.caption.weight(.semibold)).foregroundStyle(stateColor)
            Spacer()
            Text([current.assignee, current.startedAt.map { TasksView.elapsed(since: $0) }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var stateText: String {
        switch current.status {
        case "triage": return "Not started"
        case "todo": return current.parentCount > 0 ? "Waiting on another card" : "Waiting"
        case "scheduled": return "Held"
        case "ready": return "Starting"
        case "running": return "Running"
        case "blocked": return current.needsYou ? "Needs you" : "Blocked · " + (current.blockKind ?? "")
        case "review": return "In review"
        case "done": return current.lastError == nil ? "Done" : "Failed"
        case "archived": return current.completedAt == nil ? "Dropped" : "Archived"
        default: return current.status
        }
    }

    private var stateColor: Color {
        switch current.status {
        case "running", "ready": return Theme.accent
        case "blocked": return .orange
        case "done": return current.lastError == nil ? .green : Theme.rec
        default: return .secondary
        }
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 8) { Image(systemName: "link"); Text(title).font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent).glass(Theme.small)
    }

    private func session(_ id: String) -> HermesSession? {
        model.sessions.first { $0.id == id || $0.liveId == id } ?? HermesSession(id: id)
    }

    // MARK: Trail

    private var trail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(trailRows, id: \.id) { row in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(row.color).frame(width: 10, height: 10).padding(.top, 5)
                        Rectangle().fill(Theme.line).frame(width: 1).frame(maxHeight: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.text).font(.subheadline)
                        Text(row.when.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        if let q = row.quote { Text(q).font(.callout).padding(10).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 4) }
                    }
                    .padding(.bottom, 12)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    private struct TrailRow { let id: String; let text: String; let when: Date; let color: Color; let quote: String? }

    private var trailRows: [TrailRow] {
        var rows: [TrailRow] = [TrailRow(id: "created", text: "Created", when: current.createdAt, color: .secondary, quote: nil)]
        for e in detail?.events ?? [] {
            let color: Color = e.kind.contains("block") ? .orange : e.kind.contains("complet") || e.kind.contains("done") ? .green : e.kind.contains("claim") || e.kind.contains("start") ? Theme.accent : .secondary
            rows.append(TrailRow(id: "e\(e.id)", text: e.kind.replacingOccurrences(of: "_", with: " ").capitalized + (e.summary.isEmpty ? "" : " · " + e.summary), when: e.createdAt, color: color, quote: nil))
        }
        for c in detail?.comments ?? [] {
            rows.append(TrailRow(id: "c\(c.id)", text: c.author, when: c.createdAt, color: .secondary, quote: c.body))
        }
        return rows.sorted { $0.when < $1.when }
    }

    // MARK: Reply and Start

    private var replyBar: some View {
        HStack(spacing: 10) {
            TextField("Reply to \(current.assignee ?? "Hermes")", text: $reply, axis: .vertical)
                .lineLimit(1...4).focused($replyFocused)
                .padding(.horizontal, 14).padding(.vertical, 9).glass(999)
            Button { Task { await sendReply() } } label: {
                Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Theme.accent, in: Circle())
            }
            .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var startBar: some View {
        Button { Task { await start() } } label: {
            HStack(spacing: 8) { Image(systemName: CardAction.start.symbol); Text("Start · discuss it with Hermes first") }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.small, style: .continuous))
        }
        .disabled(busy)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func load() async {
        do { detail = try await tasks.detail(card) } catch { self.error = error.localizedDescription }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await work(); await load() } catch { self.error = error.localizedDescription }
    }

    private func sendReply() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await run { try await tasks.reply(current, text) }
        reply = ""
        replyFocused = false
    }

    private func start() async {
        busy = true
        defer { busy = false }
        let msg = TasksStore.startMessage(for: current, hasSkill: model.skills.skill(named: "task-grill") != nil)
        if let s = await model.startChat(msg.text, file: msg.file, title: current.title) {
            tasks.rememberSession(s.id, for: current.id)
            try? await model.settings.auth?.kanbanComment(current.id, board: current.board.isEmpty ? nil : current.board, "Discussed in talaria://chat/\(s.id)")
            path.append(InboxDestination.chat(s))
        } else {
            error = model.chat.error ?? "Could not start the chat."
        }
    }
}
