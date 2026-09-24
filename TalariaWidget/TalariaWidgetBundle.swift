import SwiftUI
import WidgetKit

@main
struct TalariaWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecorderWidget()
        RecordingLiveActivity()
        VoiceChatLiveActivity()
        RecordControl()
    }
}
