import SwiftUI

/// Switch the open session's model and reasoning effort, like the desktop's model menu.
struct ModelPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var options: ModelOptions?
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirm: (model: String, provider: String, message: String)?

    private var chat: ChatStore { model.chat }
    private var currentEffort: String { chat.currentInfo?.effort.lowercased() ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section("Effort") {
                    ForEach(ModelOptions.efforts, id: \.value) { e in
                        Button { Task { await set("reasoning", e.value) } } label: {
                            HStack { Text(e.label); Spacer(); if currentEffort == e.value { Image(systemName: "checkmark") } }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if let options {
                    ForEach(options.providers.filter { $0.authenticated && !visibleModels($0).isEmpty }) { p in
                        Section {
                            ForEach(visibleModels(p), id: \.self) { m in
                                Button { Task { await pick(m, provider: p) } } label: {
                                    HStack {
                                        Text(m)
                                        Spacer()
                                        if p.capabilities[m]?.fast == true { Image(systemName: "bolt").font(.caption).foregroundStyle(.secondary) }
                                        if p.isCurrent && m == options.model { Image(systemName: "checkmark") }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        } header: {
                            Text(p.name)
                        } footer: {
                            if let w = p.warning { Text(w) }
                        }
                    }
                } else if error == nil {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .searchable(text: $query, prompt: "Search models")
            .navigationTitle(chat.modelLabel ?? "Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(busy)
                }
            }
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { await load(refresh: false) }
            .alert("Switch model?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button("Switch") { if let c = confirm { Task { await pick(c.model, providerSlug: c.provider, confirmed: true) } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(confirm?.message ?? "") }
        }
    }

    private func visibleModels(_ p: ModelOptions.Provider) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? p.models : p.models.filter { $0.lowercased().contains(q) || p.name.lowercased().contains(q) }
    }

    private func load(refresh: Bool) async {
        busy = true
        defer { busy = false }
        do {
            options = try await chat.modelOptions(refresh: refresh)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func set(_ key: String, _ value: String) async {
        busy = true
        defer { busy = false }
        if await chat.setSessionConfig(key, value) == false { error = "Could not set \(key)." }
    }

    private func pick(_ m: String, provider p: ModelOptions.Provider) async {
        await pick(m, providerSlug: p.slug, confirmed: false)
    }

    private func pick(_ m: String, providerSlug: String, confirmed: Bool) async {
        busy = true
        defer { busy = false }
        // Same syntax as the TUI's /model: "<model> --provider <slug>".
        let value = providerSlug == options?.provider || providerSlug.isEmpty ? m : "\(m) --provider \(providerSlug)"
        guard let r = await chat.setSessionConfigResult("model", value, confirmed: confirmed) else { error = "Could not switch model."; return }
        if r["confirm_required"] as? Bool == true, !confirmed {
            confirm = (m, providerSlug, r["confirm_message"] as? String ?? "This model may be expensive.")
            return
        }
        if let w = r["warning"] as? String, !w.isEmpty { error = w } else { error = nil }
        await load(refresh: false)
    }
}
