import Foundation

// MARK: - CirclePermissions

struct CirclePermissions: Sendable, Equatable {
    let role: MemberRole
    let isActiveMember: Bool

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

    /// View-only members can read the feed but cannot post.
    var canPostActivity: Bool {
        isActiveMember && role != .viewOnly
    }

    /// Reactions are open to every active member — including view-only.
    var canReact: Bool {
        isActiveMember
    }

    /// Comments are open to every active member — including view-only.
    var canComment: Bool {
        isActiveMember
    }
}

extension CirclePermissions {
    /// Returns the permissions for the signed-in user against the given Circle.
    static func resolve(circle: Circle, appleUserID: String) -> Self {
        if circle.ownerAppleUserID == appleUserID {
            return Self(role: .owner, isActiveMember: true)
        }
        if let member = circle.members.first(where: { $0.appleUserID == appleUserID && $0.status != .removed }) {
            return Self(role: member.role, isActiveMember: member.status == .active)
        }
        return Self(role: .viewOnly, isActiveMember: false)
    }
}
