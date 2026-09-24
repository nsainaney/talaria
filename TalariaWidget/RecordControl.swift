import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control: opens Talaria and starts a recording, or stops the running one.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: RecordingShared.controlKind) {
            ControlWidgetButton(action: RecordControlIntent()) {
                Label("Record", systemImage: "record.circle")
            }
            .tint(.red)
        }
        .displayName("Record to Speakr")
        .description("Starts a recording that is sent to Speakr when it ends.")
    }
}
