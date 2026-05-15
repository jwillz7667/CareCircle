import Foundation

// MARK: - AuthProvider

/// Which sign-in path produced this session. Used by `AuthState.bootstrap`
/// to decide whether to consult `ASAuthorizationAppleIDProvider.credentialState`
/// (Apple only) or fall back to backend-refresh-token validity (email + Google).
enum AuthProvider: String, Sendable, Codable, Equatable {
    case apple
    case email
    case google
}

// MARK: - SignedInUser

struct SignedInUser: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let provider: AuthProvider
    let givenName: String?
    let familyName: String?
    let email: String?

    /// Apple's stable per-app user ID, only populated when `provider == .apple`.
    /// Required by `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`.
    let appleUserId: String?

    init(
        id: String,
        provider: AuthProvider,
        givenName: String? = nil,
        familyName: String? = nil,
        email: String? = nil,
        appleUserId: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.appleUserId = appleUserId
    }

    var displayName: String {
        let parts = [givenName, familyName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        if let email, !email.isEmpty {
            return email
        }
        return "CareCircle Member"
    }

    /// Backwards-compatible decoding: existing keychain blobs were written
    /// without `provider` / `appleUserId`. Treat those as legacy Apple sessions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        provider = try c.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .apple
        appleUserId = try c.decodeIfPresent(String.self, forKey: .appleUserId) ?? (provider == .apple ? id : nil)
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, givenName, familyName, email, appleUserId
    }
}
