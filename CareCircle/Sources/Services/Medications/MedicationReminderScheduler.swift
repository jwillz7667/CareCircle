import Foundation
import OSLog
import UserNotifications

// MARK: - MedicationReminderScheduler

/// Wraps `UNUserNotificationCenter` for medication dose reminders.
/// The scheduler builds calendar-trigger requests for the next two weeks of
/// occurrences per medication, then re-tops on app foreground (see
/// `MedicationOverdueSweeper`). Action identifiers match those registered in
/// `MedicationNotificationDelegate`.
@MainActor
struct MedicationReminderScheduler {
    nonisolated static let categoryIdentifier = "MEDICATION_DOSE"
    nonisolated static let takenActionIdentifier = "MED_TAKEN"
    nonisolated static let skippedActionIdentifier = "MED_SKIPPED"
    nonisolated static let medicationIDKey = "medicationID"
    nonisolated static let scheduledAtKey = "scheduledAt"

    let center: UNUserNotificationCenter
    var horizonDays = 14
    var maxRequestsPerMed = 16

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func registerCategoriesIfNeeded() async {
        let taken = UNNotificationAction(
            identifier: Self.takenActionIdentifier,
            title: "Taken",
            options: [.authenticationRequired]
        )
        let skipped = UNNotificationAction(
            identifier: Self.skippedActionIdentifier,
            title: "Skip",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [taken, skipped],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                AppLogger.app.error(
                    "Notification authorization failed: \(String(describing: error), privacy: .public)"
                )
                return false
            }
        @unknown default:
            return false
        }
    }

    func reschedule(medication: Medication) async {
        await cancel(medicationID: medication.id)
        guard medication.status == .active else { return }
        let occurrences = medication.schedule.upcomingOccurrences(
            after: Date(),
            limit: maxRequestsPerMed
        )
        guard !occurrences.isEmpty else { return }

        for occurrence in occurrences {
            let request = makeRequest(for: medication, at: occurrence)
            do {
                try await center.add(request)
            } catch {
                AppLogger.app.error(
                    "Failed to schedule dose reminder: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func cancel(medicationID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix(for: medicationID)) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func makeRequest(for medication: Medication, at occurrence: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.name)"
        let dosage = medication.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dosage.isEmpty {
            content.subtitle = dosage
        }
        content.body = "Tap to mark this dose."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.medicationIDKey: medication.id.uuidString,
            Self.scheduledAtKey: occurrence.timeIntervalSince1970,
        ]
        content.threadIdentifier = "med-\(medication.id.uuidString)"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: occurrence
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "\(prefix(for: medication.id))\(occurrence.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
    }

    private func prefix(for medicationID: UUID) -> String {
        "med.\(medicationID.uuidString)."
    }
}
