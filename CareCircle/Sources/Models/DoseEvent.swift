import Foundation
import SwiftData

// MARK: - DoseEvent

@Model
final class DoseEvent {
    var id = UUID()
    var scheduledAt = Date.now
    var takenAt: Date?
    var statusRaw: String = DoseStatus.scheduled.rawValue
    var markedByAppleUserID: String?
    var markedByDisplayName: String?
    var notes: String?
    var createdAt = Date.now
    var updatedAt = Date.now

    var medication: Medication?

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        scheduledAt: Date,
        status: DoseStatus = .scheduled,
        takenAt: Date? = nil,
        markedByAppleUserID: String? = nil,
        markedByDisplayName: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.scheduledAt = scheduledAt
        statusRaw = status.rawValue
        self.takenAt = takenAt
        self.markedByAppleUserID = markedByAppleUserID
        self.markedByDisplayName = markedByDisplayName
        self.notes = notes
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}
