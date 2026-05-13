import Foundation
import OSLog
import SwiftData

// MARK: - Member

@Model
final class Member {
    @Attribute(.unique) var id: UUID
    var appleUserID: String
    var displayName: String
    var roleRaw: String
    var joinedAt: Date

    var circle: Circle?

    var role: MemberRole {
        get {
            if let known = MemberRole(rawValue: roleRaw) {
                return known
            }
            let observed = roleRaw
            AppLogger.persistence.error(
                "Unknown Member role \(observed, privacy: .public); defaulting to .viewOnly"
            )
            return .viewOnly
        }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        appleUserID: String,
        displayName: String,
        role: MemberRole,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        roleRaw = role.rawValue
        self.joinedAt = joinedAt
    }
}
