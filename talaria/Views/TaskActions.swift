import SwiftUI

/// The answers on a triage item, and the actions on a card. One glyph and one tint each, used the
/// same way wherever they appear: swipes, the item toolbar, context menus, the card menu.
enum TriageAnswer: String, CaseIterable, Identifiable {
    case me, agent, done, ignore
    var id: String { rawValue }

    var title: String {
        switch self {
        case .me: return "Me"
        case .agent: return "Agent"
        case .done: return "Done"
        case .ignore: return "Ignore"
        }
    }

    var symbol: String {
        switch self {
        case .me: return "person"
        case .agent: return "cpu"
        case .done: return "checkmark"
        case .ignore: return "xmark"
        }
    }

    var tint: Color {
        switch self {
        case .me: return Theme.accent
        case .agent: return .indigo
        case .done: return .green
        case .ignore: return .gray
        }
    }

    var label: some View { Label(title, systemImage: symbol) }
}

/// Ordering, kept in the store: only an explicit move changes it.
enum MoveAction: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
    var title: String { self == .top ? "Move to top" : "Move to bottom" }
    var symbol: String { self == .top ? "arrow.up.to.line" : "arrow.down.to.line" }
    var tint: Color { .secondary }
    var label: some View { Label(title, systemImage: symbol) }
}

enum CardAction: String, CaseIterable, Identifiable {
    case start, stop, release, drop
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .release: return "Release"
        case .drop: return "Drop"
        }
    }

    var symbol: String {
        switch self {
        case .start: return "play.fill"
        case .stop: return "stop.fill"
        case .release: return "play"
        case .drop: return "archivebox"
        }
    }

    var tint: Color {
        switch self {
        case .start, .release: return Theme.accent
        case .stop: return .orange
        case .drop: return .red
        }
    }

    var label: some View { Label(title, systemImage: symbol) }

    /// Which actions a card in this status offers, in menu order.
    static func available(for card: KanbanCard) -> [CardAction] {
        switch card.status {
        case "triage", "todo": return [.start, .drop]
        case "scheduled": return [.release, .drop]
        case "ready", "running": return [.stop]
        default: return []
        }
    }
}
