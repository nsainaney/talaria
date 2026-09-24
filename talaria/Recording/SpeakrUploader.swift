import Foundation
import os

/// Uploads recordings to Speakr on a background URLSession, so a stop from the widget finishes
/// even if the app is suspended or quit meanwhile; iOS relaunches the app to deliver the result.
final class SpeakrUploader: NSObject, URLSessionDataDelegate {
    static let shared = SpeakrUploader()
    static let sessionIdentifier = "com.sainaney.talaria.speakr-upload"

    private let buffers = OSAllocatedUnfairLock<[Int: Data]>(initialState: [:])
    /// Handed over by the app delegate when iOS relaunches the app for finished transfers.
    var backgroundCompletion: (@Sendable () -> Void)?

    private(set) lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.timeoutIntervalForResource = 6 * 3600
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    func enqueue(file: URL, client: SpeakrClient) throws {
        let (request, body) = try client.uploadRequest(file: file)
        let task = session.uploadTask(with: request, fromFile: body)
        task.taskDescription = file.lastPathComponent + "\n" + body.path
        task.resume()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffers.withLock { $0[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let body = buffers.withLock { $0.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let parts = (task.taskDescription ?? "").split(separator: "\n", maxSplits: 1).map(String.init)
        let name = parts.first ?? ""
        if parts.count == 2 { try? FileManager.default.removeItem(atPath: parts[1]) }
        Task { @MainActor in
            BackgroundRecorder.shared.uploadFinished(name: name, status: status, body: body, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let done = SpeakrUploader.shared.backgroundCompletion
            SpeakrUploader.shared.backgroundCompletion = nil
            done?()
        }
    }
}
