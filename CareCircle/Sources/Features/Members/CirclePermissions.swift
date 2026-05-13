import Foundation

// MARK: - CirclePermissions

struct CirclePermissions: Sendable, Equatable {
    let role: MemberRole

    var canInviteMembers: Bool {
        role == .owner
    }

    var canRemoveMembers: Bool {
        role == .owner
    }

    var canEditCareRecipient: Bool {
        role == .owner || role == .paidFamily
    }

    var canViewMembers: Bool {
        true
    }
}

extension CirclePermissions {
    /// Returns the permissions for the signed-in user against the given Circle.
    static func resolve(circle: Circle, appleUserID: String) -> Self {
        if circle.ownerAppleUserID == appleUserID {
            return Self(role: .owner)
        }
        if let member = circle.members.first(where: { $0.appleUserID == appleUserID && $0.status != .removed }) {
            return Self(role: member.role)
        }
        return Self(role: .viewOnly)
    }
}
