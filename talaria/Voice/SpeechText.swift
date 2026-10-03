import Foundation

/// Turns reply markdown into something worth hearing: code is skipped, links read as their text,
/// list and heading markers dropped.
enum SpeechText {
    static func spoken(fromMarkdown md: String) -> String? {
        var s = md
        s = replace(s, #"```[\s\S]*?```"#, " Code omitted. ")
        s = replace(s, #"(?m)(?:^[ \t]*\|.*\|[ \t]*\n?){2,}"#, " There is a table on screen. ")
        s = replace(s, #"!\[[^\]]*\]\([^)]*\)"#, "")
        s = replace(s, #"\[([^\]]+)\]\([^)]*\)"#, "$1")
        s = replace(s, #"https?://\S+"#, "a link")
        s = replace(s, #"`([^`]*)`"#, "$1")
        s = replace(s, #"(?m)^\s{0,3}#{1,6}\s*"#, "")
        s = replace(s, #"(?m)^\s*(?:[-*+]|\d+[.)])\s+"#, "")
        s = replace(s, #"(?m)^\s*>\s?"#, "")
        s = replace(s, #"(?m)^\s*\|?[\s:|-]+\|\s*$"#, "")
        s = s.replacingOccurrences(of: "|", with: ", ")
        s = replace(s, #"[*_~]{1,3}"#, "")
        s = replace(s, #"[ \t]+"#, " ")
        s = replace(s, #"\n{2,}"#, ". ")
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = replace(s, #"\.\s*\."#, ".")
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// A command or description short enough to read aloud.
    static func brief(_ text: String, limit: Int = 160) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count <= limit ? one : String(one.prefix(limit)) + ", and so on"
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}

/// Accumulates streamed markdown and hands out complete sentences as they close, so speech can
/// start before the reply finishes. Nothing inside an open code fence is released.
struct SpeechSentenceSplitter {
    private var buffer = ""
    private(set) var receivedAny = false

    mutating func push(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        buffer += text
        receivedAny = true
        guard buffer.components(separatedBy: "```").count % 2 == 1 else { return [] }
        guard let cut = Self.lastBoundary(in: buffer) else { return [] }
        let head = String(buffer[..<cut])
        buffer = String(buffer[cut...])
        return SpeechText.spoken(fromMarkdown: head).map { [$0] } ?? []
    }

    mutating func flush() -> [String] {
        let rest = buffer
        buffer = ""
        return SpeechText.spoken(fromMarkdown: rest).map { [$0] } ?? []
    }

    /// Index just past the last sentence end: ".", "!" or "?" followed by whitespace, or a newline.
    private static func lastBoundary(in s: String) -> String.Index? {
        var result: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(after: i)
            if s[i] == "\n" {
                result = next
            } else if ".!?".contains(s[i]), next < s.endIndex, s[next].isWhitespace {
                result = next
            }
            i = next
        }
        return result
    }
}
