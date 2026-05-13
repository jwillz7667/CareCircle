import Foundation

// MARK: - AppointmentDraft

/// Scratchpad mirroring the editable fields of an `Appointment`. Held in
/// `@State` by `AddAppointmentView` so SwiftData isn't touched until the user
/// confirms.
struct AppointmentDraft: Equatable {
    var title = ""
    var provider = ""
    var location = ""
    var startsAt: Date = Self.defaultStart()
    var durationMinutes = 60
    var prepNotes = ""
    var visitSummary = ""
    var transportResponsibleAppleUserID: String?
    var transportResponsibleDisplayName: String?
    var reminderOffsetsMinutes: [Int] = [1_440, 60]
    var mirrorToCalendar = false
    var markCompleted = false
    var completedAt: Date?

    init() {}

    init(appointment: Appointment, mirrorToCalendar: Bool) {
        title = appointment.title
        provider = appointment.provider ?? ""
        location = appointment.location ?? ""
        startsAt = appointment.startsAt
        durationMinutes = appointment.durationMinutes
        prepNotes = appointment.prepNotes ?? ""
        visitSummary = appointment.visitSummary ?? ""
        transportResponsibleAppleUserID = appointment.transportResponsibleAppleUserID
        transportResponsibleDisplayName = appointment.transportResponsibleDisplayName
        reminderOffsetsMinutes = appointment.reminderOffsetsMinutes
        self.mirrorToCalendar = mirrorToCalendar
        markCompleted = appointment.completedAt != nil
        completedAt = appointment.completedAt
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProvider: String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPrepNotes: String {
        prepNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedVisitSummary: String {
        visitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedTitle.isEmpty && (5 ... 720).contains(durationMinutes)
    }

    func apply(to appointment: Appointment, now: Date = .now) {
        appointment.title = trimmedTitle
        appointment.provider = trimmedProvider.isEmpty ? nil : trimmedProvider
        appointment.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        appointment.startsAt = startsAt
        appointment.durationMinutes = durationMinutes
        appointment.prepNotes = trimmedPrepNotes.isEmpty ? nil : trimmedPrepNotes
        appointment.visitSummary = trimmedVisitSummary.isEmpty ? nil : trimmedVisitSummary
        appointment.transportResponsibleAppleUserID = transportResponsibleAppleUserID
        appointment.transportResponsibleDisplayName = transportResponsibleDisplayName
        appointment.reminderOffsetsMinutes = reminderOffsetsMinutes
        appointment.completedAt = resolvedCompletedAt(now: now)
        appointment.updatedAt = now
    }

    private func resolvedCompletedAt(now: Date) -> Date? {
        if markCompleted {
            completedAt ?? now
        } else {
            nil
        }
    }

    private static func defaultStart() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = 10
        components.minute = 0
        let base = calendar.date(from: components) ?? .now
        return base < .now ? calendar.date(byAdding: .day, value: 1, to: base) ?? base : base
    }
}

// MARK: - Reminder offset presets

enum AppointmentReminderPreset: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case oneHour = 60
    case threeHours = 180
    case oneDay = 1_440
    case twoDays = 2_880
    case oneWeek = 10_080

    var id: Int {
        rawValue
    }

    var displayName: String {
        switch self {
        case .fifteenMinutes: "15 minutes before"
        case .oneHour: "1 hour before"
        case .threeHours: "3 hours before"
        case .oneDay: "1 day before"
        case .twoDays: "2 days before"
        case .oneWeek: "1 week before"
        }
    }
}
