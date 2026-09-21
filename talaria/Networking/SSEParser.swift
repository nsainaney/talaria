import Foundation

/// Minimal Server-Sent Events frame parser. Feed it lines; it emits (event, data) pairs on blank lines.
/// Comment lines (starting with ":") such as Hermes' `: keepalive` are ignored.
struct SSEParser {
    private var event: String?
    private var data: [String] = []

    mutating func feed(line: String) -> (event: String?, data: String)? {
        if line.isEmpty {
            defer { event = nil; data = [] }
            guard !data.isEmpty else { return nil }
            return (event, data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }
}
