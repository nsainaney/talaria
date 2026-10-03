import SwiftUI
import MarkdownUI

/// An assistant message split into markdown and the `card` / `rule` blocks Hermes writes, so a
/// proposed task or reminder renders as itself with its one strong action.
struct AssistantBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.segments(text).enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .markdown(let md): MarkdownText(text: md)
                case .card(let c): ProposedCardView(card: c)
                case .rule(let r): ProposedRuleView(yaml: r)
                }
            }
        }
    }

    enum Segment { case markdown(String), card(ProposedCard), rule(String) }

    /// Fenced blocks tagged `card` or `rule` become their own segments; everything else stays markdown.
    static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var md: [String] = []
        var block: [String]?
        var blockKind = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if block == nil, t == "```card" || t == "```rule" {
                if !md.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.markdown(md.joined(separator: "\n"))) }
                md = []
                block = []
                blockKind = String(t.dropFirst(3))
                continue
            }
            if block != nil, t == "```" {
                let body = block!.joined(separator: "\n")
                out.append(blockKind == "card" ? .card(ProposedCard(yaml: body)) : .rule(body))
                block = nil
                continue
            }
            if block != nil { block!.append(line) } else { md.append(line) }
        }
        if let block {
            // Still streaming: show the unfinished block as code so nothing flickers into a half card.
            md.append("```" + blockKind)
            md += block
            md.append("```")
        }
        if !md.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || out.isEmpty { out.append(.markdown(md.joined(separator: "\n"))) }
        return out
    }
}

/// The markdown part, styled as before.
struct MarkdownText: View {
    let text: String
    var body: some View {
        Markdown(text)
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                BackgroundColor(Color(.secondarySystemBackground))
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .padding(12)
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 4, bottom: 8)
            }
            .textSelection(.enabled)
    }
}

/// A task or reminder Hermes proposed: dashed until it exists. Proceed files the task and sets it
/// ready; Add to Reminders writes the reminder. Edit opens the fields.
struct ProposedCardView: View {
    @Environment(AppModel.self) private var model
    let card: ProposedCard
    @State private var draft: ProposedCard
    @State private var editing = false
    @State private var busy = false
    @State private var done: String?
    @State private var error: String?
    @State private var assignees: [String] = []

    init(card: ProposedCard) {
        self.card = card
        _draft = State(initialValue: card)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: draft.kind == .reminder ? "bell" : draft.kind == .issue ? "smallcircle.filled.circle" : "cpu")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(headline).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(done == nil ? "proposed" : done!).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(done == nil ? Theme.accent.opacity(0.12) : Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(done == nil ? Theme.accent : .green)
            }
            Text(draft.title).font(.subheadline.weight(.semibold))
            if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
            if !draft.body.isEmpty {
                Text(draft.body).font(.footnote).lineLimit(editing ? nil : 4).foregroundStyle(.primary.opacity(0.85))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if done == nil {
                HStack(spacing: 18) {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }.foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await go() } } label: {
                        Label(draft.kind == .reminder ? "Add to Reminders" : "Proceed", systemImage: draft.kind == .reminder ? "bell" : "play.fill")
                    }
                    .disabled(busy)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(done == nil ? Theme.accent.opacity(0.5) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: done == nil ? [5, 4] : [])))
        .padding(.horizontal)
        .sheet(isPresented: $editing) { editor }
    }

    private var headline: String {
        switch draft.kind {
        case .task: return [draft.assignee, draft.board].compactMap { $0 }.joined(separator: " · ").ifEmpty("task")
        case .reminder: return draft.list ?? "Reminders"
        case .issue: return "GitHub issue"
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let c = draft.closes, !c.isEmpty { parts.append("closes " + Self.short(c)) }
        if let d = draft.due { parts.append(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + (draft.time.map { " " + $0 } ?? " · all day")) }
        if !draft.tags.isEmpty { parts.append(draft.tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    private static func short(_ url: String) -> String {
        if let r = url.range(of: "github.com/") {
            let rest = url[r.upperBound...].split(separator: "/")
            if rest.count >= 4 { return "\(rest[1]) #\(rest[3])" }
        }
        return url
    }

    private func go() async {
        busy = true
        defer { busy = false }
        do {
            switch draft.kind {
            case .task:
                let c = try await model.tasks.proceed(draft, sessionId: model.chat.session?.id)
                done = "filed · " + c.id
            case .reminder:
                let comps: DateComponents? = draft.time.flatMap { t in
                    let p = t.split(separator: ":"); guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
                    return DateComponents(hour: h, minute: m)
                }
                var notes = draft.body
                if !draft.tags.isEmpty { notes += "\n" + draft.tags.map { "#" + $0 }.joined(separator: " ") }
                _ = try await RemindersWriter.shared.add(title: draft.title, day: draft.due ?? Date(), time: comps,
                                                         listId: nil, url: draft.url.flatMap(URL.init(string:)), notes: notes)
                done = "added"
            case .issue:
                error = "Creating issues is done on GitHub; open the repo and paste the title and body."
            }
        } catch TasksStore.TaskError.needsAssignee {
            self.error = TasksStore.TaskError.needsAssignee.localizedDescription
            editing = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var editor: some View {
        let assignee = Binding(get: { draft.assignee ?? "" }, set: { draft.assignee = $0.isEmpty ? nil : $0 })
        return NavigationStack {
            Form {
                TextField("Title", text: $draft.title)
                if draft.kind == .task {
                    if assignees.isEmpty {
                        TextField("Assignee (hermes, coder-vm)", text: assignee)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    } else {
                        Picker("Assignee", selection: assignee) {
                            Text("Choose").tag("")
                            ForEach(assignees + (assignee.wrappedValue.isEmpty || assignees.contains(assignee.wrappedValue) ? [] : [assignee.wrappedValue]), id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                    }
                }
                TextField(draft.kind == .reminder ? "Notes" : "Body", text: $draft.body, axis: .vertical).lineLimit(4...16)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
            .task { if draft.kind == .task, assignees.isEmpty { assignees = await model.tasks.assignees() } }
        }
    }
}

/// A screener rule Hermes proposed in a Why chat. Save is done by Hermes on request, so this only
/// shows it as a rule and offers the word.
struct ProposedRuleView: View {
    @Environment(AppModel.self) private var model
    let yaml: String

    var body: some View {
        let r = ProposedCard(yaml: yaml)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Screener rule").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let scope = r.extra["scope"] { Text(scope).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Text(r.extra["rule"] ?? yaml).font(.subheadline)
            HStack {
                Spacer()
                Button { Task { await model.chat.send("Save the rule.", skills: model.skills) } } label: { Label("Save rule", systemImage: "checkmark") }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .padding(.horizontal)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
