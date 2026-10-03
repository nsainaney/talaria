import Foundation

/// Uploads a recording to Speakr (`POST /api/v1/recordings/upload`, bearer API token).
/// Speakr transcribes and summarizes it; Hermes reads the result through its Speakr skill.
nonisolated struct SpeakrClient: Sendable {
    let baseURL: URL
    let token: String

    struct Uploaded: Sendable {
        let id: Int
        /// The recording's page in Speakr's web UI.
        let pageURL: URL
    }

    enum Error: LocalizedError {
        case http(Int, String)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Speakr returned HTTP \(code): \(body)"
            case .badResponse: return "Speakr returned an unexpected response"
            }
        }
    }

    func pageURL(id: Int) -> URL { baseURL.appendingPathComponent("recordings/\(id)") }

    /// Checks the URL and token together: `GET /api/v1/users/me` answers with the token's user.
    func whoAmI() async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/users/me"))
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Error.badResponse }
        guard http.statusCode == 200 else {
            let text = http.statusCode == 401 ? "invalid or expired token" : (String(data: data.prefix(120), encoding: .utf8) ?? "")
            throw Error.http(http.statusCode, text)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["username"] as? String else { throw Error.badResponse }
        return name
    }

    /// The upload request with its multipart body written to a temporary file, as background
    /// transfers need. The caller deletes the body file when the transfer is done.
    func uploadRequest(file: URL, notes: String? = nil) throws -> (URLRequest, URL) {
        let boundary = "talaria-" + UUID().uuidString
        let dir = URL.cachesDirectory.appendingPathComponent("SpeakrUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bodyURL = dir.appendingPathComponent(UUID().uuidString + ".body")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: bodyURL)
        defer { try? out.close() }

        func field(_ name: String, _ value: String) throws {
            try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        if let notes, !notes.isEmpty { try field("notes", notes) }
        let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        try field("file_last_modified", String(Int(mod.timeIntervalSince1970 * 1000)))
        try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/recordings/upload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return (req, bodyURL)
    }

    /// Foreground upload, for the meeting screen.
    func upload(file: URL, notes: String? = nil) async throws -> Uploaded {
        let (req, body) = try uploadRequest(file: file, notes: notes)
        defer { try? FileManager.default.removeItem(at: body) }
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: body)
        guard let http = resp as? HTTPURLResponse else { throw Error.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        guard let id = Self.recordingId(from: data) else { throw Error.badResponse }
        return Uploaded(id: id, pageURL: pageURL(id: id))
    }

    /// Speakr answers with the recording as JSON; the id is at the top level (or nested under `recording`).
    static func recordingId(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let id = json["id"] as? Int { return id }
        return (json["recording"] as? [String: Any])?["id"] as? Int
    }
}
