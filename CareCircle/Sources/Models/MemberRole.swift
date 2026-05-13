import Foundation

// MARK: - MemberRole

enum MemberRole: String, Codable, CaseIterable, Sendable, Equatable {
    case owner
    case familyMember = "family_member"
    case paidAide = "paid_aide"
    case paidFamily = "paid_family"
    case careRecipient = "care_recipient"
    case viewOnly = "view_only"

    var displayName: String {
        switch self {
        case .owner: "Primary caregiver"
        case .familyMember: "Family member"
        case .paidAide: "Paid aide"
        case .paidFamily: "Paid family caregiver"
        case .careRecipient: "Care recipient"
        case .viewOnly: "View only"
        }
    }
}
