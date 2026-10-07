import SwiftUI

final class MusicManagerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        QueuePersistenceStore.removeLegacyKeys()
        TempFileJanitor.sweepStaleFiles()
        return true
    }
}

@main
struct MusicManagerApp: App {
    @UIApplicationDelegateAdaptor(MusicManagerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
