import CloudKit
import OSLog
import UIKit

// MARK: - CircleSceneDelegate

final class CircleSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(
        _: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let metadata = cloudKitShareMetadata
        Task { @MainActor in
            do {
                try await CircleSharingService.shared.acceptShare(metadata: metadata)
                AppLogger.cloudKit
                    .info("Share accepted for record \(metadata.share.recordID.recordName, privacy: .public)")
            } catch {
                AppLogger.cloudKit.error(
                    "Share acceptance failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
