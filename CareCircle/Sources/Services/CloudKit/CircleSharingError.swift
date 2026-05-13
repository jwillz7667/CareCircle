import Foundation

// MARK: - CircleSharingError

enum CircleSharingError: LocalizedError, Sendable, Equatable {
    case notSignedIntoiCloud
    case capReached(limit: Int)
    case ckFailure(String)
    case invalidShareMetadata

    var errorDescription: String? {
        switch self {
        case .notSignedIntoiCloud:
            "Sign in to iCloud in Settings to invite Circle members."
        case let .capReached(limit):
            "This Circle is full (\(limit) members)."
        case let .ckFailure(message):
            "CloudKit error: \(message)"
        case .invalidShareMetadata:
            "This invitation link is invalid or has expired."
        }
    }
}
