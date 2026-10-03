import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control: a toggle that starts and stops a recording.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: RecordingShared.controlKind, provider: RecordControlProvider()) { isOn in
            ControlWidgetToggle("Record", isOn: isOn, action: ToggleRecordingIntent()) { on in
                Label(on ? "Recording" : "Record", systemImage: on ? "stop.circle.fill" : "record.circle")
            }
            .tint(.red)
        }
        .displayName("Record to Speakr")
        .description("Start or stop a recording that is sent to Speakr when it ends.")
    }
}

nonisolated struct RecordControlProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { RecordingState.load().isActive }
}
