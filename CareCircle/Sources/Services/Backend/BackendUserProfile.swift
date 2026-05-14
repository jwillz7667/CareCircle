import Foundation

// MARK: - BackendUserProfile

/// Decoded payload from `GET /v1/me`. Mirrors the columns the backend
/// returns from its `users` table; `email` is `nil` whenever the user
/// signed in with Apple's private-relay address but the caller asked
/// not to share it.
nonisolated struct BackendUserProfile: Codable, Sendable, Equatable {
    let id: String
    let email: String?
    let displayName: String?
    let photoObjectKey: String?
    let isPrivateEmail: Bool
    let createdAt: Date
}
