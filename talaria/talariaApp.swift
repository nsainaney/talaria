import SwiftUI
import UIKit

@main
struct talariaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRecorder.shared.prepare()
        return true
    }

    /// iOS relaunched or woke the app because a Speakr upload finished.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping @Sendable () -> Void) {
        SpeakrUploader.shared.backgroundCompletion = completionHandler
        _ = SpeakrUploader.shared.session
    }
}
