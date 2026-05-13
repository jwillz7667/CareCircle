import Foundation
import SwiftData

// MARK: - Circle

@Model
final class Circle {
    var id = UUID()
    var name = ""
    var ownerAppleUserID = ""
    var createdAt = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CareRecipient.circle)
    var careRecipient: CareRecipient?

    @Relationship(deleteRule: .cascade, inverse: \Member.circle)
    var members: [Member] = []

    @Relationship(deleteRule: .cascade, inverse: \Activity.circle)
    var activities: [Activity] = []

    @Relationship(deleteRule: .cascade, inverse: \Medication.circle)
    var medications: [Medication] = []

    @Relationship(deleteRule: .cascade, inverse: \Appointment.circle)
    var appointments: [Appointment] = []

    @Relationship(deleteRule: .cascade, inverse: \Document.circle)
    var documents: [Document] = []

    @Relationship(deleteRule: .cascade, inverse: \SOSEvent.circle)
    var sosEvents: [SOSEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.circle)
    var emergencyContacts: [EmergencyContact] = []

    init(
        id: UUID = UUID(),
        name: String,
        ownerAppleUserID: String,
        createdAt: Date = .now,
        careRecipient: CareRecipient? = nil,
        members: [Member] = [],
        activities: [Activity] = [],
        medications: [Medication] = [],
        appointments: [Appointment] = [],
        documents: [Document] = [],
        sosEvents: [SOSEvent] = [],
        emergencyContacts: [EmergencyContact] = []
    ) {
        self.id = id
        self.name = name
        self.ownerAppleUserID = ownerAppleUserID
        self.createdAt = createdAt
        self.careRecipient = careRecipient
        self.members = members
        self.activities = activities
        self.medications = medications
        self.appointments = appointments
        self.documents = documents
        self.sosEvents = sosEvents
        self.emergencyContacts = emergencyContacts
    }
}
