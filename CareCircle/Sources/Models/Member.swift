import Foundation
import OSLog
import SwiftData

// MARK: - Member

@Model
final class Member {
    var id = UUID()
    var appleUserID = ""
    var displayName = ""
    var roleRaw: String = MemberRole.viewOnly.rawValue
    var statusRaw: String = MemberStatus.active.rawValue
    var joinedAt = Date.now
    var invitedAt: Date?
    var invitedByAppleUserID: String?
    var acceptedAt: Date?
    var inviteShareURLString: String?

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

    var status: MemberStatus {
        get {
            if let known = MemberStatus(rawValue: statusRaw) {
                return known
            }
            let observed = statusRaw
            AppLogger.persistence.error(
                "Unknown Member status \(observed, privacy: .public); defaulting to .removed"
            )
            return .removed
        }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        appleUserID: String,
        displayName: String,
        role: MemberRole,
        status: MemberStatus = .active,
        joinedAt: Date = .now,
        invitedAt: Date? = nil,
        invitedByAppleUserID: String? = nil,
        acceptedAt: Date? = nil,
        inviteShareURLString: String? = nil
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        roleRaw = role.rawValue
        statusRaw = status.rawValue
        self.joinedAt = joinedAt
        self.invitedAt = invitedAt
        self.invitedByAppleUserID = invitedByAppleUserID
        self.acceptedAt = acceptedAt
        self.inviteShareURLString = inviteShareURLString
    }
}
