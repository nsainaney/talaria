import Foundation
import WidgetKit

/// Names shared by the app and its widget extension.
nonisolated enum RecordingShared {
    static let appGroup = "group.com.sainaney.talaria"
    static let widgetKind = "TalariaRecorder"
    static let controlKind = "TalariaRecordControl"
    static let stateKey = "recording.state"
    /// Opens the app and starts a recording, for when the widget cannot start one itself.
    static let recordURL = URL(string: "talaria://record")!

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

/// What the recorder is doing, as the widget, the Live Activity and the app show it.
/// Written by the app into the app group; read by the widget extension.
nonisolated struct RecordingState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case idle, recording, paused, uploading, sent, failed, startFailed }

    var phase: Phase = .idle
    /// While recording: now minus the seconds already recorded, so a timer view shows the total.
    var timerStart: Date?
    /// Seconds recorded at the last pause or stop.
    var recorded: TimeInterval = 0
    var fileName: String?
    /// A call or another app took the microphone; recording resumes by itself when it ends.
    var interrupted = false
    /// Outcome after a stop: where it went, or why it did not.
    var message: String?
    var speakrRecordingId: Int?
    /// The app already has microphone permission, so the widget can start recording without opening it.
    var micGranted = false
    var speakrConfigured = false

    var isActive: Bool { phase == .recording || phase == .paused }

    static func load() -> RecordingState {
        guard let data = RecordingShared.defaults.data(forKey: RecordingShared.stateKey),
              let s = try? JSONDecoder().decode(RecordingState.self, from: data) else { return RecordingState() }
        return s
    }

    @MainActor func save() {
        if let data = try? JSONEncoder().encode(self) {
            RecordingShared.defaults.set(data, forKey: RecordingShared.stateKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: RecordingShared.widgetKind)
        ControlCenter.shared.reloadControls(ofKind: RecordingShared.controlKind)
    }

    static func stamp(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
