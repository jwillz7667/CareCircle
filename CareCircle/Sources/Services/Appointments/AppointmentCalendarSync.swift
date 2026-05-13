import EventKit
import Foundation
import OSLog

// MARK: - AppointmentCalendarSync

/// Optional EventKit mirror: when the user opts an `Appointment` into the
/// system Calendar, `upsert(for:)` writes a corresponding `EKEvent` to the
/// device's default calendar and stores its identifier in `UserDefaults`
/// keyed on the appointment UUID. EKEvent identifiers are not portable
/// across devices, so we keep the mapping local — each device that opts in
/// creates its own mirror.
@MainActor
final class AppointmentCalendarSync {
    static let shared = AppointmentCalendarSync()

    private let store = EKEventStore()
    private let storage: UserDefaults
    private let storageKey = "carecircle.appointment.calendarMirror.v1"

    init(storage: UserDefaults = .standard) {
        self.storage = storage
    }

    enum SyncError: LocalizedError {
        case accessDenied
        case noCalendarAvailable
        case eventKitError(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "CareCircle doesn't have access to your Calendar. Enable it in Settings → CareCircle."
            case .noCalendarAvailable:
                "No writable calendar is available on this device."
            case let .eventKitError(message):
                message
            }
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            AppLogger.app.error(
                "EventKit access request failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    func hasAccess() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess: true
        case .writeOnly, .notDetermined, .restricted, .denied: false
        @unknown default: false
        }
    }

    func upsert(for appointment: Appointment) async throws {
        if !hasAccess() {
            let granted = await requestAccess()
            guard granted else { throw SyncError.accessDenied }
        }
        guard let calendar = store.defaultCalendarForNewEvents ?? firstWritableCalendar() else {
            throw SyncError.noCalendarAvailable
        }

        let existingID = identifier(for: appointment.id)
        let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = appointment.title
        event.location = appointment.location
        event.notes = composedNotes(for: appointment)
        event.startDate = appointment.startsAt
        event.endDate = appointment.endsAt
        event.alarms = appointment.reminderOffsetsMinutes.map {
            EKAlarm(relativeOffset: -TimeInterval($0) * 60)
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            AppLogger.app.error(
                "EventKit save failed: \(String(describing: error), privacy: .public)"
            )
            throw SyncError.eventKitError(error.localizedDescription)
        }
        setIdentifier(event.eventIdentifier, for: appointment.id)
    }

    func remove(for appointmentID: UUID) async {
        guard let eventID = identifier(for: appointmentID),
              hasAccess(),
              let event = store.event(withIdentifier: eventID) else
        {
            clearIdentifier(for: appointmentID)
            return
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            AppLogger.app.error(
                "EventKit remove failed: \(String(describing: error), privacy: .public)"
            )
        }
        clearIdentifier(for: appointmentID)
    }

    func isMirroring(_ appointmentID: UUID) -> Bool {
        identifier(for: appointmentID) != nil
    }

    private func firstWritableCalendar() -> EKCalendar? {
        store.calendars(for: .event).first { $0.allowsContentModifications }
    }

    private func composedNotes(for appointment: Appointment) -> String? {
        var lines: [String] = []
        if let provider = appointment.provider?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty
        {
            lines.append("Provider: \(provider)")
        }
        if let transport = appointment.transportResponsibleDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !transport.isEmpty
        {
            lines.append("Transport: \(transport)")
        }
        if let prep = appointment.prepNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prep.isEmpty
        {
            lines.append("Prep: \(prep)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func identifier(for appointmentID: UUID) -> String? {
        let map = storage.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        return map[appointmentID.uuidString]
    }

    private func setIdentifier(_ eventID: String, for appointmentID: UUID) {
        var map = storage.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        map[appointmentID.uuidString] = eventID
        storage.set(map, forKey: storageKey)
    }

    private func clearIdentifier(for appointmentID: UUID) {
        var map = storage.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        map.removeValue(forKey: appointmentID.uuidString)
        storage.set(map, forKey: storageKey)
    }
}
