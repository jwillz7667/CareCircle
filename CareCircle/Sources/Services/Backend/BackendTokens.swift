import Foundation

// MARK: - BackendTokens

/// Token pair returned by `POST /v1/auth/apple` and `POST /v1/auth/refresh`.
/// Stored in the Keychain as a single JSON blob so a single read/write
/// keeps both halves consistent.
nonisolated struct BackendTokens: Codable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let userId: String?

    /// Conservative early-renewal: refresh 60s before the server claims
    /// expiry to avoid races with in-flight requests.
    var isAccessTokenStale: Bool {
        accessTokenExpiresAt.timeIntervalSinceNow < 60
    }

    var isRefreshTokenExpired: Bool {
        refreshTokenExpiresAt <= .now
    }
}

// MARK: - Token DTOs (wire format)

nonisolated struct AppleAuthRequest: Encodable, Sendable {
    let identityToken: String
    let nonce: String?
    let givenName: String?
    let familyName: String?
}

nonisolated struct EmailRegisterRequest: Encodable, Sendable {
    let email: String
    let password: String
    let displayName: String?
}

nonisolated struct EmailLoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct GoogleAuthRequest: Encodable, Sendable {
    let idToken: String
}

nonisolated struct RefreshAuthRequest: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct LogoutRequest: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct BackendAuthResponse: Decodable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let userId: String?
}
