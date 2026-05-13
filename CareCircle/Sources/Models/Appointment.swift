import Foundation
import SwiftData

// MARK: - Appointment

@Model
final class Appointment {
    var id = UUID()
    var title = ""
    var provider: String?
    var location: String?
    var startsAt = Date.now
    var durationMinutes = 60
    var prepNotes: String?
    var visitSummary: String?
    var transportResponsibleAppleUserID: String?
    var transportResponsibleDisplayName: String?
    var reminderOffsetsMinutes: [Int] = [1_440, 60]
    var completedAt: Date?
    var createdByAppleUserID = ""
    var createdByDisplayName = ""
    var createdAt = Date.now
    var updatedAt = Date.now

    var circle: Circle?

    init(
        id: UUID = UUID(),
        title: String,
        provider: String? = nil,
        location: String? = nil,
        startsAt: Date,
        durationMinutes: Int = 60,
        prepNotes: String? = nil,
        visitSummary: String? = nil,
        transportResponsibleAppleUserID: String? = nil,
        transportResponsibleDisplayName: String? = nil,
        reminderOffsetsMinutes: [Int] = [1_440, 60],
        completedAt: Date? = nil,
        createdByAppleUserID: String,
        createdByDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.location = location
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.prepNotes = prepNotes
        self.visitSummary = visitSummary
        self.transportResponsibleAppleUserID = transportResponsibleAppleUserID
        self.transportResponsibleDisplayName = transportResponsibleDisplayName
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        self.completedAt = completedAt
        self.createdByAppleUserID = createdByAppleUserID
        self.createdByDisplayName = createdByDisplayName
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var endsAt: Date {
        startsAt.addingTimeInterval(TimeInterval(durationMinutes) * 60)
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}
