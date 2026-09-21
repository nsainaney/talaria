import Foundation
import Observation

@Observable @MainActor
final class SkillsStore {
    private static let pinnedKey = "hermes.pinnedSkills"

    var skills: [Skill] = []
    var pinned: [String] {
        didSet { UserDefaults.standard.set(pinned, forKey: Self.pinnedKey) }
    }
    var isLoading = false
    var error: String?

    init() {
        pinned = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []
    }

    func load(client: HermesClient?) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await client.skills()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func isPinned(_ skill: Skill) -> Bool { pinned.contains(skill.name) }

    func togglePin(_ skill: Skill) {
        if let i = pinned.firstIndex(of: skill.name) { pinned.remove(at: i) } else { pinned.append(skill.name) }
    }

    /// Pinned first, then the rest, filtered by a case-insensitive substring on name/description/category.
    func filtered(_ query: String) -> [Skill] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = skills.filter { s in
            q.isEmpty || s.name.lowercased().contains(q)
                || (s.description ?? "").lowercased().contains(q)
                || (s.category ?? "").lowercased().contains(q)
        }
        let pinnedSet = Set(pinned)
        let top = matches.filter { pinnedSet.contains($0.name) }
        let rest = matches.filter { !pinnedSet.contains($0.name) }
        return top + rest
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The API server does not expand `/skill` slash commands the way the CLI and messaging
    /// gateways do, so an invocation is sent as an explicit instruction to load the skill.
    static func invocationText(skill: Skill, instruction: String) -> String {
        var text = "[The user has invoked the \"\(skill.name)\" skill. Load it with your skills tool and follow its instructions.]"
        let rest = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { text += "\n\n" + rest }
        return text
    }
}
