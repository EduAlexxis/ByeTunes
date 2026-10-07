import SwiftUI
import UniformTypeIdentifiers

extension MusicView {
    var progressCounterText: String {
        if shouldHideQueueDuringLargeInjection {
            return totalInjectCount > 0 ? "\(currentInjectIndex)/\(totalInjectCount)" : "0/0"
        }
        if shouldHideQueueDuringLargeImport {
            return totalImportCount > 0 ? "\(currentImportIndex)/\(totalImportCount)" : "0/0"
        }
        if shouldUseCompactQueueForLargeBatch {
            return "\(songs.count) queued"
        }
        return totalImportCount > 0 ? "\(currentImportIndex)/\(totalImportCount)" : "0/0"
    }

    var progressValue: Double {
        if shouldHideQueueDuringLargeInjection {
            guard totalInjectCount > 0 else { return 0 }
            return Double(currentInjectIndex) / Double(totalInjectCount)
        }
        if shouldHideQueueDuringLargeImport {
            guard totalImportCount > 0 else { return 0 }
            return Double(currentImportIndex) / Double(totalImportCount)
        }
        if shouldUseCompactQueueForLargeBatch {
            return 1
        }
        guard totalImportCount > 0 else { return 0 }
        return Double(currentImportIndex) / Double(totalImportCount)
    }

    var progressRingValue: CGFloat {
        CGFloat(min(max(progressValue, 0), 1))
    }

    var progressPrimaryText: String {
        if shouldHideQueueDuringLargeInjection {
            return totalInjectCount > 0 ? "\(currentInjectIndex)" : "0"
        }
        if shouldHideQueueDuringLargeImport {
            return totalImportCount > 0 ? "\(currentImportIndex)" : "0"
        }
        if shouldUseCompactQueueForLargeBatch {
            return "\(songs.count)"
        }
        return "0"
    }

    var compactQueueTitle: String {
        if shouldHideQueueDuringLargeInjection {
            return "Injecting Songs"
        }
        if shouldHideQueueDuringLargeImport {
            return importPhaseTitle
        }
        return "Large Batch Ready"
    }

    var compactQueueSubtitle: String {
        if shouldHideQueueDuringLargeInjection {
            return "Large batch mode keeps the queue lightweight while injection finishes."
        }
        if shouldHideQueueDuringLargeImport {
            return "Large import mode keeps the queue hidden until everything is ready."
        }
        return "Use Review Batch Metadata to make edits before injecting."
    }

    func showToast(title: String, icon: String) {
        withAnimation(.spring()) {
            self.toastTitle = title
            self.toastIcon = icon
            self.showToast = true
        }
        
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.showToast = false
            }
        }
    }
}
