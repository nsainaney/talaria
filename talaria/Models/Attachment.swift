import UIKit
import UniformTypeIdentifiers

/// Something queued in the composer. The Hermes API accepts inline images only, so any other
/// file has to be text that can be pasted into the message.
enum Attachment {
    case image(UIImage)
    case text(name: String, contents: String)

    private static let maxTextBytes = 256 * 1024

    enum LoadError: LocalizedError {
        case unreadable(String), unsupported(String), tooLarge(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let n): return "Could not read \(n)."
            case .unsupported(let n): return "\(n): Hermes accepts images and text files only."
            case .tooLarge(let n): return "\(n) is larger than 256 KB."
            }
        }
    }

    /// Load a Files-app pick. Images become image parts; UTF-8 text becomes an inline block.
    static func load(from url: URL) -> Result<Attachment, LoadError> {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable(name)) }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true, let img = UIImage(data: data) {
            return .success(.image(img))
        }
        if data.count > maxTextBytes { return .failure(.tooLarge(name)) }
        let looksTextual = type.map { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) || $0.conforms(to: .json) || $0.conforms(to: .xml) || $0.conforms(to: .yaml) } ?? false
        if let text = String(data: data, encoding: .utf8), looksTextual || !text.contains("\0") {
            return .success(.text(name: name, contents: text))
        }
        return .failure(.unsupported(name))
    }
}
