import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - MedicationNotificationDelegate

/// Receives medication notification taps + quick actions and dispatches into
/// SwiftData. Installed on `UNUserNotificationCenter.current().delegate` from
/// `CircleSceneDelegate` (which already owns scene-level wiring).
@MainActor
final class MedicationNotificationDelegate: NSObject {
    private let containerProvider: () -> ModelContainer?
    private let logger = AppLogger.app

    init(containerProvider: @escaping () -> ModelContainer?) {
        self.containerProvider = containerProvider
        super.init()
    }
}

extension MedicationNotificationDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let medIDString = userInfo[MedicationReminderScheduler.medicationIDKey] as? String
        let scheduledAt = userInfo[MedicationReminderScheduler.scheduledAtKey] as? TimeInterval

        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self,
                  let medIDString,
                  let medicationID = UUID(uuidString: medIDString),
                  let scheduledAt else { return }
            let scheduledDate = Date(timeIntervalSince1970: scheduledAt)
            switch actionID {
            case MedicationReminderScheduler.takenActionIdentifier:
                applyDoseResult(medicationID: medicationID, scheduledDate: scheduledDate, status: .taken)
            case MedicationReminderScheduler.skippedActionIdentifier:
                applyDoseResult(medicationID: medicationID, scheduledDate: scheduledDate, status: .skipped)
            default:
                break
            }
        }
    }

    private func applyDoseResult(
        medicationID: UUID,
        scheduledDate: Date,
        status: DoseStatus
    ) {
        guard let container = containerProvider() else {
            logger.error("ModelContainer unavailable for notification action.")
            return
        }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == medicationID }
        )
        do {
            guard let medication = try context.fetch(descriptor).first else { return }
            DoseEventApplicator.apply(
                status: status,
                scheduledAt: scheduledDate,
                medication: medication,
                in: context,
                marker: nil
            )
            try context.save()
            logger.info("Applied \(status.rawValue, privacy: .public) from notification.")
        } catch {
            logger.error(
                "Notification action failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
