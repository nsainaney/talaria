import SwiftUI

/// One thing that came in: the source, why the screener surfaced it, a link to open it, and the
/// three answers as a light toolbar: Me, Agent, Ignore.
struct TaskItemView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Binding var path: NavigationPath
    let entry: TriageEntry
    @State private var showRemind = false
    @State private var showIgnore = false
    @State private var busy = false
    @State private var error: String?

    private var tasks: TasksStore { model.tasks }
    private var item: ContextItem { entry.item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: item.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(item.sourceLine).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.ts.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                if !item.body.isEmpty {
                    Text(item.body).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).glass(Theme.small)
                }
                if let c = entry.candidate, !c.why.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Why it is here").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.accent)
                        Text(c.why).font(.callout)
                        if let d = c.suggestedDue {
                            Text("Suggested: " + d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let u = item.url.flatMap(URL.init(string:)) {
                    Button { openURL(u) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol)
                            Text(openLabel).font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).glass(Theme.small)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(GlassBackground())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(MoveAction.allCases) { m in
                        Button { Task { try? await tasks.move(entry, to: m.rawValue) } } label: { m.label }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .confirmationDialog("Ignore this?", isPresented: $showIgnore, titleVisibility: .visible) {
            Button("Ignore") { Task { await run { try await tasks.ignore(entry) } } }
            Button("Ignore and tell Hermes why") { Task { await ignoreAndExplain() } }
        } message: {
            Text("Telling Hermes why turns this into a rule, so the screener stops surfacing things like it.")
        }
        .sheet(isPresented: $showRemind) {
            RemindSheet(entry: entry) { day, time, list in
                await run { try await tasks.remind(entry, day: day, time: time, listId: list) }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var openLabel: String {
        switch item.source {
        case "office365", "google": return "Open in Mail"
        case "imessage": return "Open in Messages"
        case "github": return "Open on GitHub"
        case "speakr": return "Open the recording"
        default: return "Open"
        }
    }

    private var actions: some View {
        HStack {
            ForEach(TriageAnswer.allCases) { a in
                action(a.title, a.symbol, a.tint) {
                    switch a {
                    case .me: showRemind = true
                    case .agent: Task { await run { try await tasks.agent(entry) } }
                    case .done: Task { await run { try await tasks.markDone(entry) } }
                    case .ignore: showIgnore = true
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .disabled(busy)
    }

    private func action(_ title: String, _ symbol: String, _ color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 22, weight: .regular))
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ignore, then a chat with the screener-feedback skill in place of this screen.
    private func ignoreAndExplain() async {
        busy = true
        defer { busy = false }
        do { try await tasks.ignore(entry) } catch { self.error = error.localizedDescription; return }
        let msg = TasksStore.whyMessage(for: entry, decision: "ignore", hasSkill: model.skills.skill(named: "screener-feedback") != nil)
        guard let s = await model.startChat(msg.text, file: msg.file, title: "Why ignore · " + entry.title) else {
            error = model.chat.error ?? "Could not start the chat."
            return
        }
        if !path.isEmpty { path.removeLast() }
        path.append(InboxDestination.chat(s))
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            if !path.isEmpty { path.removeLast() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Me: a day, a time if wanted, which Reminders list. Then Reminders owns it.
struct RemindSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TriageEntry
    let commit: (_ day: Date, _ time: DateComponents?, _ listId: String?) async -> Void
    @State private var day = Date()
    @State private var atTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var lists: [RemindersWriter.List] = []
    @State private var listId: String?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(quick, id: \.title) { q in
                        Button {
                            day = q.date
                        } label: {
                            HStack {
                                Text(q.title)
                                Spacer()
                                Text(q.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).foregroundStyle(.secondary)
                                if Calendar.current.isDate(day, inSameDayAs: q.date) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    DatePicker("Another day", selection: $day, displayedComponents: .date)
                }
                Section {
                    Toggle("At a time", isOn: $atTime)
                    if atTime { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                    Picker("List", selection: $listId) {
                        ForEach(lists) { l in Text(l.title).tag(Optional(l.id)) }
                    }
                } footer: {
                    Text("Goes into Reminders with the source link and \(entry.item.sourceTag). It leaves Triage; Reminders takes it from here.")
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Adding…" : "Add to Reminders") {
                        Task {
                            busy = true
                            let comps = atTime ? Calendar.current.dateComponents([.hour, .minute], from: time) : nil
                            await commit(day, comps, listId)
                            busy = false
                            dismiss()
                        }
                    }
                    .disabled(busy)
                }
            }
            .task {
                if let d = entry.candidate?.suggestedDue, d > Date() { day = d } else { day = quick.first?.date ?? Date() }
                do {
                    lists = try await RemindersWriter.shared.lists()
                    listId = lists.first?.id
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private var quick: [(title: String, date: Date)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(String, Date)] = [("Today", today), ("Tomorrow", cal.date(byAdding: .day, value: 1, to: today)!)]
        if let d = entry.candidate?.suggestedDue, d > today, !out.contains(where: { cal.isDate($0.1, inSameDayAs: d) }) { out.append(("Suggested", d)) }
        var monday = today
        repeat { monday = cal.date(byAdding: .day, value: 1, to: monday)! } while cal.component(.weekday, from: monday) != 2
        if !out.contains(where: { cal.isDate($0.1, inSameDayAs: monday) }) { out.append(("Next Monday", monday)) }
        return out
    }
}
