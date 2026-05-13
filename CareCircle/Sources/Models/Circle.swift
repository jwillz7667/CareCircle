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

    init(
        id: UUID = UUID(),
        name: String,
        ownerAppleUserID: String,
        createdAt: Date = .now,
        careRecipient: CareRecipient? = nil,
        members: [Member] = [],
        activities: [Activity] = []
    ) {
        self.id = id
        self.name = name
        self.ownerAppleUserID = ownerAppleUserID
        self.createdAt = createdAt
        self.careRecipient = careRecipient
        self.members = members
        self.activities = activities
    }
}
