import EventKit
import Foundation

/// Writes the reminders that "Me" creates, and completes them when a card finishes. Reminders is
/// the record for human tasks; Talaria only writes what triage decided.
@MainActor
final class RemindersWriter {
    static let shared = RemindersWriter()
    private let store = EKEventStore()

    struct List: Identifiable, Hashable {
        let id: String
        let title: String
        let color: CGColor?
    }

    enum Error: LocalizedError {
        case denied
        var errorDescription: String? { "Talaria needs access to Reminders. Allow it in Settings › Privacy › Reminders." }
    }

    private func ensureAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        default:
            let ok = try await store.requestFullAccessToReminders()
            guard ok else { throw Error.denied }
        }
    }

    func lists() async throws -> [List] {
        try await ensureAccess()
        let def = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .sorted { ($0.calendarIdentifier == def ? 0 : 1, $0.title) < ($1.calendarIdentifier == def ? 0 : 1, $1.title) }
            .map { List(id: $0.calendarIdentifier, title: $0.title, color: $0.cgColor) }
    }

    var defaultListId: String? { store.defaultCalendarForNewReminders()?.calendarIdentifier }

    /// Creates the reminder and returns its identifier (the `reminder:<id>` decision target).
    /// `time` nil makes an all-day reminder on `day`; with a time, an alarm fires then.
    func add(title: String, day: Date, time: DateComponents?, listId: String?, url: URL?, notes: String) async throws -> String {
        try await ensureAccess()
        let r = EKReminder(eventStore: store)
        r.title = title
        r.notes = notes
        r.url = url
        r.calendar = listId.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if let time {
            comps.hour = time.hour
            comps.minute = time.minute
            if let date = Calendar.current.date(from: comps) { r.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        r.dueDateComponents = comps
        try store.save(r, commit: true)
        return r.calendarItemIdentifier
    }

    /// Marks a reminder done and appends a line to its notes; a missing reminder is not an error.
    func complete(id: String, note: String?) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted = true
        if let note, !note.isEmpty { r.notes = ((r.notes ?? "") + "\n" + note).trimmingCharacters(in: .whitespacesAndNewlines) }
        try store.save(r, commit: true)
    }

    func remove(id: String) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(r, commit: true)
    }

    func reminder(id: String) -> EKReminder? { store.calendarItem(withIdentifier: id) as? EKReminder }
}
