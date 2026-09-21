import SwiftUI

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let err = model.skills.error { Text(err).foregroundStyle(.red) }
                ForEach(model.skills.filtered(query)) { skill in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(skill.name).font(.body.monospaced())
                                if let c = skill.category, !c.isEmpty {
                                    Text(c).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                            if let d = skill.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { model.skills.togglePin(skill) } label: {
                            Image(systemName: model.skills.isPinned(skill) ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.borderless)
                        Button("Invoke") {
                            NotificationCenter.default.post(name: .invokeSkill, object: skill.name)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
            .listStyle(.plain)
            .overlay { if model.skills.isLoading && model.skills.skills.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "Search skills")
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.skills.load(client: model.client) } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { if model.skills.skills.isEmpty { await model.skills.load(client: model.client) } }
        }
    }
}
