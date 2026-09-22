import Foundation
import Observation

/// A built-in slash command (`/model`, `/reasoning`, `/help`, …) from the server's completion list.
struct SlashCommand: Identifiable, Hashable {
    let name: String
    var description: String?
    var id: String { name }
}

@Observable @MainActor
final class SkillsStore {
    var skills: [Skill] = []
    var commands: [SlashCommand] = []
    var isLoading = false
    var error: String?

    let pins: PinStore

    init(pins: PinStore) { self.pins = pins }

    /// Names and categories come from `skills.manage list`; descriptions from the slash
    /// completion list, which is what the TUI's `/` popup shows.
    func load(client: GatewayClient) async {
        guard client.isConnected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var byName: [String: Skill] = [:]
            let listed = try await client.request("skills.manage", ["action": "list"])
            for (category, names) in listed["skills"] as? [String: [String]] ?? [:] {
                for n in names { byName[n] = Skill(name: n, description: nil, category: category) }
            }
            var builtins: [SlashCommand] = []
            if let completions = try? await client.request("complete.slash", ["text": "/"]) {
                for item in completions["items"] as? [[String: Any]] ?? [] {
                    let kind = item["kind"] as? String ?? ""
                    let raw = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                    let name = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
                    guard !name.isEmpty else { continue }
                    if kind == "command" {
                        if !builtins.contains(where: { $0.name == name }) { builtins.append(SlashCommand(name: name, description: item["meta"] as? String)) }
                        continue
                    }
                    guard kind == "skill" || kind == "bundle" else { continue }
                    var s = byName[name] ?? Skill(name: name, description: nil, category: kind == "bundle" ? "bundle" : nil)
                    s.description = item["meta"] as? String
                    byName[name] = s
                }
            }
            skills = byName.values.sorted { ($0.category ?? "", $0.name) < ($1.category ?? "", $1.name) }
            commands = builtins
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func isPinned(_ skill: Skill) -> Bool { pins.isSkillPinned(skill.name) }
    func togglePin(_ skill: Skill) { pins.toggleSkill(skill.name) }

    /// Pinned first, then the rest, filtered by a case-insensitive substring on name/description/category.
    func filtered(_ query: String) -> [Skill] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = skills.filter { s in
            q.isEmpty || s.name.lowercased().contains(q)
                || (s.description ?? "").lowercased().contains(q)
                || (s.category ?? "").lowercased().contains(q)
        }
        return matches.filter { isPinned($0) } + matches.filter { !isPinned($0) }
    }

    /// Built-in commands whose name starts with the query (server order, which is by usage).
    func commands(matching query: String) -> [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return commands.filter { q.isEmpty || $0.name.lowercased().hasPrefix(q) }
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
