import Foundation
import SwiftData

// MARK: - Circle

@Model
final class Circle {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerAppleUserID: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CareRecipient.circle)
    var careRecipient: CareRecipient?

    @Relationship(deleteRule: .cascade, inverse: \Member.circle)
    var members: [Member]

    init(
        id: UUID = UUID(),
        name: String,
        ownerAppleUserID: String,
        createdAt: Date = .now,
        careRecipient: CareRecipient? = nil,
        members: [Member] = []
    ) {
        self.id = id
        self.name = name
        self.ownerAppleUserID = ownerAppleUserID
        self.createdAt = createdAt
        self.careRecipient = careRecipient
        self.members = members
    }
}
