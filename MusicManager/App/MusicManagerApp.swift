import SwiftUI
import BackgroundTasks

final class MusicManagerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundMetadataFetchManager.shared.registerBackgroundTask()
        TempFileJanitor.sweepStaleFiles()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundMetadataFetchManager.shared.scheduleBackgroundProcessing()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == MetadataBackgroundURLSession.sessionIdentifier {
            guard BackgroundMetadataFetchManager.isEnabled else {
                completionHandler()
                return
            }
            MetadataBackgroundURLSession.shared.setBackgroundEventsCompletionHandler(completionHandler)
            BackgroundMetadataFetchManager.shared.processPendingDownloadsInBackground()
            return
        }

        guard identifier == BackgroundAudioDownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }

        guard UserDefaults.standard.bool(forKey: "backgroundDownloadsEnabled") else {
            completionHandler()
            return
        }

        BackgroundAudioDownloadManager.shared.setBackgroundEventsCompletionHandler(completionHandler)
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
