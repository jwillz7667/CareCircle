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

    /// SwiftData + CloudKit requires to-many relationships to be optional.
    /// We keep optional `*Store` properties as the CloudKit-facing storage
    /// and expose non-optional `members`, `activities`, ... via computed
    /// accessors so the rest of the app reads them as ordinary `[Foo]`.
    @Relationship(deleteRule: .cascade, inverse: \Member.circle)
    var membersStore: [Member]?

    @Relationship(deleteRule: .cascade, inverse: \Activity.circle)
    var activitiesStore: [Activity]?

    @Relationship(deleteRule: .cascade, inverse: \Medication.circle)
    var medicationsStore: [Medication]?

    @Relationship(deleteRule: .cascade, inverse: \Appointment.circle)
    var appointmentsStore: [Appointment]?

    @Relationship(deleteRule: .cascade, inverse: \Document.circle)
    var documentsStore: [Document]?

    @Relationship(deleteRule: .cascade, inverse: \SOSEvent.circle)
    var sosEventsStore: [SOSEvent]?

    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.circle)
    var emergencyContactsStore: [EmergencyContact]?

    @Relationship(deleteRule: .cascade, inverse: \CareMinuteEntry.circle)
    var careMinuteEntriesStore: [CareMinuteEntry]?

    @Relationship(deleteRule: .cascade, inverse: \ShiftDigest.circle)
    var shiftDigestsStore: [ShiftDigest]?

    @Relationship(deleteRule: .cascade, inverse: \Insight.circle)
    var insightsStore: [Insight]?

    var members: [Member] {
        get { membersStore ?? [] }
        set { membersStore = newValue }
    }

    var activities: [Activity] {
        get { activitiesStore ?? [] }
        set { activitiesStore = newValue }
    }

    var medications: [Medication] {
        get { medicationsStore ?? [] }
        set { medicationsStore = newValue }
    }

    var appointments: [Appointment] {
        get { appointmentsStore ?? [] }
        set { appointmentsStore = newValue }
    }

    var documents: [Document] {
        get { documentsStore ?? [] }
        set { documentsStore = newValue }
    }

    var sosEvents: [SOSEvent] {
        get { sosEventsStore ?? [] }
        set { sosEventsStore = newValue }
    }

    var emergencyContacts: [EmergencyContact] {
        get { emergencyContactsStore ?? [] }
        set { emergencyContactsStore = newValue }
    }

    var careMinuteEntries: [CareMinuteEntry] {
        get { careMinuteEntriesStore ?? [] }
        set { careMinuteEntriesStore = newValue }
    }

    var shiftDigests: [ShiftDigest] {
        get { shiftDigestsStore ?? [] }
        set { shiftDigestsStore = newValue }
    }

    var insights: [Insight] {
        get { insightsStore ?? [] }
        set { insightsStore = newValue }
    }

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
        emergencyContacts: [EmergencyContact] = [],
        careMinuteEntries: [CareMinuteEntry] = [],
        shiftDigests: [ShiftDigest] = []
    ) {
        self.id = id
        self.name = name
        self.ownerAppleUserID = ownerAppleUserID
        self.createdAt = createdAt
        self.careRecipient = careRecipient
        membersStore = members
        activitiesStore = activities
        medicationsStore = medications
        appointmentsStore = appointments
        documentsStore = documents
        sosEventsStore = sosEvents
        emergencyContactsStore = emergencyContacts
        careMinuteEntriesStore = careMinuteEntries
        shiftDigestsStore = shiftDigests
    }
}
