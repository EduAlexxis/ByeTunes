import Foundation
import BackgroundTasks
import UIKit

private final class ContinuedTaskExpiryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false

    var isExpired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expired
    }

    func markExpired() {
        lock.lock()
        expired = true
        lock.unlock()
    }
}

@MainActor
final class ContinuedDownloadTask {
    static let shared = ContinuedDownloadTask()

    private var isRunning = false
    private var unavailableForSession = false

    func startIfNeeded(for viewModel: DownloadViewModel) {
        guard #available(iOS 26.0, *) else { return }
        guard !isRunning, !unavailableForSession else { return }
        guard UserDefaults.standard.bool(forKey: "backgroundDownloadsEnabled") else { return }
        guard viewModel.hasPendingOrActiveDownloads, !viewModel.isPaused else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10))
        let identifier = "\(bundleID).download.\(suffix)"
        isRunning = true

        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self, weak viewModel] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else { return }
            Task { @MainActor in
                await self?.run(continuedTask, viewModel: viewModel)
            }
        }
        guard registered else {
            isRunning = false
            Logger.shared.log("[ContinuedTask] Registration rejected for \(identifier); identifier is not permitted by Info.plist")
            return
        }

        Task.detached { [weak self] in
            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier,
                title: "Downloading music",
                subtitle: "Starting..."
            )
            request.strategy = .fail

            do {
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
                Logger.shared.log("[ContinuedTask] Submission accepted for \(identifier)")
            } catch {
                let nsError = error as NSError
                Logger.shared.log("[ContinuedTask] Submission failed domain=\(nsError.domain) code=\(nsError.code): \(nsError.localizedDescription)")
                await MainActor.run {
                    if nsError.domain == BGTaskScheduler.errorDomain, nsError.code == BGTaskScheduler.Error.unavailable.rawValue {
                        self?.unavailableForSession = true
                    }
                    let refreshStatus: String
                    switch UIApplication.shared.backgroundRefreshStatus {
                    case .available: refreshStatus = "available"
                    case .denied: refreshStatus = "denied"
                    case .restricted: refreshStatus = "restricted"
                    @unknown default: refreshStatus = "unknown"
                    }
                    Logger.shared.log("[ContinuedTask] Context: backgroundRefresh=\(refreshStatus) lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled) appState=\(UIApplication.shared.applicationState.rawValue)")
                    self?.isRunning = false
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func run(_ task: BGContinuedProcessingTask, viewModel: DownloadViewModel?) async {
        Logger.shared.log("[ContinuedTask] Task started")
        let expiry = ContinuedTaskExpiryFlag()
        task.expirationHandler = {
            expiry.markExpired()
        }

        var highestCompleted: Int64 = 0

        while !expiry.isExpired {
            guard let viewModel, viewModel.hasPendingOrActiveDownloads, !viewModel.isPaused else { break }

            let snapshot = viewModel.continuedTaskProgress()
            highestCompleted = max(highestCompleted, snapshot.completedUnits)
            task.progress.totalUnitCount = snapshot.totalUnits
            task.progress.completedUnitCount = min(highestCompleted, snapshot.totalUnits)
            task.updateTitle("Downloading music", subtitle: snapshot.subtitle)

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        isRunning = false

        if expiry.isExpired {
            Logger.shared.log("[ContinuedTask] Task cancelled from the system interface; pausing queue")
            viewModel?.pauseQueue()
            task.setTaskCompleted(success: false)
        } else {
            Logger.shared.log("[ContinuedTask] Task finished")
            if let viewModel {
                let snapshot = viewModel.continuedTaskProgress()
                task.progress.totalUnitCount = snapshot.totalUnits
                task.progress.completedUnitCount = snapshot.totalUnits
            }
            task.setTaskCompleted(success: true)
        }
    }
}
