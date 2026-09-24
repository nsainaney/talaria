import AVFoundation
import Foundation
import Observation
import os

/// The recordings kept in Files › Talaria › Meetings, with what Speakr knows about each.
/// Files older than 30 days are deleted on refresh.
@Observable @MainActor
final class RecordingLibrary {
    static let shared = RecordingLibrary()
    static let retention: TimeInterval = 30 * 24 * 3600

    struct Item: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let url: URL
        let date: Date
        let size: Int64
        let duration: TimeInterval?
        var sentId: Int?
        var sentAt: Date?
        var sending = false
        var error: String?
        var title: String?
        var isSent: Bool { sentId != nil }
        var displayTitle: String { title ?? "Recording" }
    }

    private(set) var items: [Item] = []

    private struct Sent: Codable { var id: Int; var at: Date }
    @ObservationIgnored private var sent: [String: Sent] = [:]
    @ObservationIgnored private var sending: Set<String> = []
    @ObservationIgnored private var errors: [String: String] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.sainaney.talaria", category: "library")
    private static let sentKey = "recordings.sent"
    private static let titlesKey = "recordings.titles"
    @ObservationIgnored private var titles: [String: String] = [:]

    /// Documents/Meetings, visible in the Files app.
    static func directory() -> URL {
        let dir = URL.documentsDirectory.appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func rename(_ name: String, to title: String) {
        if title.isEmpty || title == "Recording" { titles[name] = nil } else { titles[name] = title }
        UserDefaults.standard.set(titles, forKey: Self.titlesKey)
        refresh()
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.sentKey),
           let s = try? JSONDecoder().decode([String: Sent].self, from: data) { sent = s }
        titles = UserDefaults.standard.dictionary(forKey: Self.titlesKey) as? [String: String] ?? [:]
    }

    /// Re-read the folder, drop files past the retention period, and rebuild the list.
    func refresh(keeping active: String? = nil) {
        let dir = Self.directory()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        var list: [Item] = []
        for url in urls where url.pathExtension.lowercased() == "m4a" {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let date = v?.creationDate ?? v?.contentModificationDate ?? Date()
            if url.lastPathComponent != active, Date().timeIntervalSince(date) > Self.retention {
                log.info("deleting \(url.lastPathComponent, privacy: .public): older than 30 days")
                try? FileManager.default.removeItem(at: url)
                sent[url.lastPathComponent] = nil
                continue
            }
            let name = url.lastPathComponent
            let duration = name == active ? nil : (try? AVAudioPlayer(contentsOf: url))?.duration
            list.append(Item(name: name, url: url, date: date, size: Int64(v?.fileSize ?? 0), duration: duration,
                             sentId: sent[name]?.id, sentAt: sent[name]?.at, sending: sending.contains(name), error: errors[name], title: titles[name]))
        }
        items = list.sorted { $0.date > $1.date }
        // Forget sent records for files that no longer exist.
        let names = Set(items.map(\.name))
        sent = sent.filter { names.contains($0.key) }
        persist()
    }

    /// The recorder started an upload of this file itself.
    func noteSending(_ name: String) { sending.insert(name); errors[name] = nil }

    func send(_ item: Item, client: SpeakrClient) {
        do {
            try SpeakrUploader.shared.enqueue(file: item.url, client: client)
            sending.insert(item.name)
            errors[item.name] = nil
        } catch {
            errors[item.name] = error.localizedDescription
        }
        refresh()
    }

    func delete(_ item: Item) {
        if PlaybackPlayer.shared.playingName == item.name { PlaybackPlayer.shared.stop() }
        try? FileManager.default.removeItem(at: item.url)
        sent[item.name] = nil
        errors[item.name] = nil
        titles[item.name] = nil
        refresh()
    }

    func markSent(name: String, id: Int) {
        sent[name] = Sent(id: id, at: Date())
        persist()
        refresh()
    }

    /// Called by the uploader for every finished transfer, then handed on to the live recorder.
    func uploadFinished(name: String, status: Int?, body: Data, error: (any Error)?) {
        sending.remove(name)
        if error == nil, let status, (200..<300).contains(status), let id = SpeakrClient.recordingId(from: body) {
            sent[name] = Sent(id: id, at: Date())
            errors[name] = nil
        } else {
            errors[name] = error?.localizedDescription ?? "Speakr returned HTTP \(status ?? 0)"
        }
        persist()
        refresh()
        BackgroundRecorder.shared.uploadFinished(name: name, status: status, body: body, error: error)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sent) { UserDefaults.standard.set(data, forKey: Self.sentKey) }
    }
}
