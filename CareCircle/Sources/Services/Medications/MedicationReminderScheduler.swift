import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - MedicationReminderScheduler

/// Wraps `UNUserNotificationCenter` for medication dose reminders.
/// The scheduler builds calendar-trigger requests for the next two weeks of
/// occurrences per medication, then re-tops on app foreground (see
/// `rescheduleActiveMeds(in:)`, called from `RootView`). Action identifiers
/// match those registered in `MedicationNotificationDelegate`.
@MainActor
struct MedicationReminderScheduler {
    nonisolated static let categoryIdentifier = "MEDICATION_DOSE"
    nonisolated static let takenActionIdentifier = "MED_TAKEN"
    nonisolated static let skippedActionIdentifier = "MED_SKIPPED"
    nonisolated static let medicationIDKey = "medicationID"
    nonisolated static let scheduledAtKey = "scheduledAt"

    /// iOS keeps at most 64 pending local-notification requests per app and
    /// silently drops everything past the ceiling. Dose reminders share that
    /// budget with appointment reminders, so we cap the medication slice
    /// below 64 and distribute it across active meds rather than letting one
    /// med schedule 16 requests and starve the rest.
    nonisolated static let maxPendingMedicationRequests = 56

    nonisolated static let identifierPrefix = "med."

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
        let existing = await center.notificationCategories()
        var merged = existing
        merged.insert(category)
        center.setNotificationCategories(merged)
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

    /// Reschedules a single medication. The per-med request count is clamped
    /// to whatever remains of the app-wide medication budget after the other
    /// active meds, so adding the Nth med can never push the total past the
    /// 64-request OS ceiling. For a full rebalance across all meds, prefer
    /// `rescheduleActiveMeds(in:)`.
    func reschedule(medication: Medication) async {
        await cancel(medicationID: medication.id)
        guard medication.status == .active else { return }
        let budget = await remainingMedicationBudget()
        guard budget > 0 else {
            AppLogger.app.notice("Dose-reminder budget exhausted; skipping reminders for this med.")
            return
        }
        let occurrences = medication.schedule.upcomingOccurrences(
            after: Date(),
            limit: min(maxRequestsPerMed, budget)
        )
        await add(occurrences: occurrences, for: medication)
    }

    /// Rebalances the entire medication-reminder budget across the currently
    /// active meds and re-tops the horizon. Called on foreground so reminders
    /// stay fresh past the initial two-week window and so a med added while
    /// another held most of the budget gets its fair share on the next pass.
    func rescheduleActiveMeds(in context: ModelContext) async {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.statusRaw == "active" }
        )
        let active = (try? context.fetch(descriptor)) ?? []
        await cancelAll()
        guard !active.isEmpty else { return }

        let perMed = max(1, min(maxRequestsPerMed, Self.maxPendingMedicationRequests / active.count))
        for medication in active {
            let occurrences = medication.schedule.upcomingOccurrences(after: Date(), limit: perMed)
            await add(occurrences: occurrences, for: medication)
        }
    }

    func cancel(medicationID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix(for: medicationID)) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Drops every pending dose reminder across all medications.
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Remaining slots in the medication budget, computed from what is
    /// currently pending. Call after cancelling the med being rescheduled so
    /// its own stale requests don't count against it.
    private func remainingMedicationBudget() async -> Int {
        let pending = await center.pendingNotificationRequests()
        let used = pending.lazy.count(where: { $0.identifier.hasPrefix(Self.identifierPrefix) })
        return max(0, Self.maxPendingMedicationRequests - used)
    }

    private func add(occurrences: [Date], for medication: Medication) async {
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

    private func makeRequest(for medication: Medication, at occurrence: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.name)"
        let dosage = medication.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dosage.isEmpty {
            content.subtitle = dosage
        }
        content.body = "Tap to mark this dose."
        content.sound = .default
        // A missed dose is time-critical for the care recipient; break through
        // scheduled-summary batching so the reminder surfaces on time.
        content.interruptionLevel = .timeSensitive
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
        "\(Self.identifierPrefix)\(medicationID.uuidString)."
    }
}
