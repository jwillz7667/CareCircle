import CloudKit
import OSLog
import UIKit
import UserNotifications

// MARK: - CircleSceneDelegate

final class CircleSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) {
        Task { @MainActor in
            installMedicationNotificationDelegate()
        }
    }

    @MainActor
    private func installMedicationNotificationDelegate() {
        if MedicationServices.shared.notificationDelegate != nil { return }
        let delegate = MedicationNotificationDelegate {
            MedicationServices.shared.currentContainer()
        }
        MedicationServices.shared.install(notificationDelegate: delegate)
        UNUserNotificationCenter.current().delegate = delegate
        Task {
            await MedicationReminderScheduler().registerCategoriesIfNeeded()
        }
    }

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
