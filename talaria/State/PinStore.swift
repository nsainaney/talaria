import Foundation
import Observation

/// Pinned session and skill ids. Stored locally in UserDefaults; the personal signing team
/// cannot use iCloud, so cross-device sync (NSUbiquitousKeyValueStore) is a later upgrade.
@Observable @MainActor
final class PinStore {
    static let sessionsKey = "pins.sessions"
    static let skillsKey = "pins.skills"

    private(set) var sessions: [String]
    private(set) var skills: [String]

    init() {
        sessions = UserDefaults.standard.stringArray(forKey: Self.sessionsKey) ?? []
        skills = UserDefaults.standard.stringArray(forKey: Self.skillsKey) ?? []
    }

    func isSessionPinned(_ id: String) -> Bool { sessions.contains(id) }
    func isSkillPinned(_ name: String) -> Bool { skills.contains(name) }

    func toggleSession(_ id: String) {
        if let i = sessions.firstIndex(of: id) { sessions.remove(at: i) } else { sessions.append(id) }
        UserDefaults.standard.set(sessions, forKey: Self.sessionsKey)
    }

    func toggleSkill(_ name: String) {
        if let i = skills.firstIndex(of: name) { skills.remove(at: i) } else { skills.append(name) }
        UserDefaults.standard.set(skills, forKey: Self.skillsKey)
    }
}
