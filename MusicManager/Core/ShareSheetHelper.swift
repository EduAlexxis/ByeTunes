import SwiftUI
import UIKit

struct ShareSheetHelper {
    static func share(items: [Any], onFinished: (() -> Void)? = nil) {
        guard !items.isEmpty else {
            onFinished?()
            return
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let onFinished {
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                onFinished()
            }
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first,
            let rootVC = windowScene.windows.filter({ $0.isKeyWindow }).first?.rootViewController else {
            onFinished?()
            return
        }

        var topVC = rootVC
        while let presentedVC = topVC.presentedViewController {
            topVC = presentedVC
        }

        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = topVC.view
            popoverController.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true, completion: nil)
    }
}
