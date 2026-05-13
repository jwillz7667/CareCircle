import Foundation

// MARK: - MemberStatus

enum MemberStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case active
    case invited
    case removed

    var displayName: String {
        switch self {
        case .active: "Active"
        case .invited: "Invited"
        case .removed: "Removed"
        }
    }
}
