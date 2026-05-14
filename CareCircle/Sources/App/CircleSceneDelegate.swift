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
                if let circleID = Self.circleID(from: metadata) {
                    await CircleDocumentKeySyncService.shared.pullIfMissing(circleID: circleID)
                }
            } catch {
                AppLogger.cloudKit.error(
                    "Share acceptance failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Parses the shared zone name (`circle-<uuid>`) out of the metadata
    /// so we can target a DEK pull at the just-accepted circle. Returns
    /// nil for any zone the app didn't create.
    private static func circleID(from metadata: CKShare.Metadata) -> UUID? {
        let zoneName = metadata.share.recordID.zoneID.zoneName
        let prefix = "circle-"
        guard zoneName.hasPrefix(prefix) else { return nil }
        let suffix = String(zoneName.dropFirst(prefix.count))
        return UUID(uuidString: suffix)
    }
}
