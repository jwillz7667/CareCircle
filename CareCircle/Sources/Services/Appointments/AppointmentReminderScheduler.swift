import Foundation
import OSLog
import UserNotifications

// MARK: - AppointmentReminderScheduler

/// Wraps `UNUserNotificationCenter` for appointment reminders. The scheduler
/// issues one calendar-trigger request per reminder offset on the appointment,
/// indexed by `(appointmentID, offsetMinutes)`. Mirrors
/// `MedicationReminderScheduler` for code parity.
@MainActor
struct AppointmentReminderScheduler {
    nonisolated static let categoryIdentifier = "APPOINTMENT_REMINDER"
    nonisolated static let viewActionIdentifier = "APPT_VIEW"
    nonisolated static let appointmentIDKey = "appointmentID"
    nonisolated static let scheduledAtKey = "scheduledAt"

    let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func registerCategoriesIfNeeded() async {
        let view = UNNotificationAction(
            identifier: Self.viewActionIdentifier,
            title: "View",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [view],
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
                    "Appointment notification auth failed: \(String(describing: error), privacy: .public)"
                )
                return false
            }
        @unknown default:
            return false
        }
    }

    func reschedule(appointment: Appointment) async {
        await cancel(appointmentID: appointment.id)
        guard appointment.completedAt == nil,
              !appointment.reminderOffsetsMinutes.isEmpty else { return }

        let now = Date()
        for offsetMinutes in appointment.reminderOffsetsMinutes {
            let fireDate = appointment.startsAt.addingTimeInterval(-TimeInterval(offsetMinutes) * 60)
            guard fireDate > now else { continue }
            let request = makeRequest(for: appointment, fireDate: fireDate, offsetMinutes: offsetMinutes)
            do {
                try await center.add(request)
            } catch {
                AppLogger.app.error(
                    "Appointment reminder schedule failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func cancel(appointmentID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix(for: appointmentID)) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func makeRequest(
        for appointment: Appointment,
        fireDate: Date,
        offsetMinutes: Int
    )
        -> UNNotificationRequest
    {
        let content = UNMutableNotificationContent()
        content.title = appointment.title
        if let location = appointment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty
        {
            content.subtitle = location
        }
        content.body = bodyText(for: appointment, offsetMinutes: offsetMinutes)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.appointmentIDKey: appointment.id.uuidString,
            Self.scheduledAtKey: appointment.startsAt.timeIntervalSince1970,
        ]
        content.threadIdentifier = "appt-\(appointment.id.uuidString)"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "\(prefix(for: appointment.id))\(offsetMinutes)",
            content: content,
            trigger: trigger
        )
    }

    private func bodyText(for appointment: Appointment, offsetMinutes: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let timeString = formatter.localizedString(fromTimeInterval: TimeInterval(offsetMinutes) * 60)
        let provider = appointment.provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let provider, !provider.isEmpty {
            return "With \(provider) in \(timeString)"
        }
        return "Starts in \(timeString)"
    }

    private func prefix(for appointmentID: UUID) -> String {
        "appt.\(appointmentID.uuidString)."
    }
}
