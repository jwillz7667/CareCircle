import Foundation

// MARK: - AuthStatus

enum AuthStatus: Sendable, Equatable {
    case unknown
    case signedOut
    case signedIn(SignedInUser)
}
