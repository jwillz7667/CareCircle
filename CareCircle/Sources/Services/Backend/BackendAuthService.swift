import Foundation
import OSLog

// MARK: - BackendAuthService

/// Thin facade over `APIClient` that turns an Apple identity token into
/// a backend session and surfaces the inverse operations (refresh on
/// demand, logout). Stateless apart from the injected client — safe to
/// hand around as a value.
nonisolated struct BackendAuthService: Sendable {
    let apiClient: APIClient

    /// Exchanges an Apple identity token for a backend access/refresh
    /// pair and persists it. The `nonce` argument is the SHA-256 hash
    /// passed to `ASAuthorizationAppleIDRequest.nonce` — it must equal
    /// the `nonce` claim baked into `identityToken` so the backend
    /// verifier accepts it.
    func exchangeAppleIdentity(
        identityToken: String,
        nonce: String?,
        givenName: String?,
        familyName: String?
    ) async throws(APIError) {
        let request = AppleAuthRequest(
            identityToken: identityToken,
            nonce: nonce,
            givenName: givenName,
            familyName: familyName
        )
        let response: BackendAuthResponse = try await apiClient.send(
            method: .post,
            path: "/v1/auth/apple",
            body: request,
            authenticated: false
        )
        let tokens = BackendTokens(
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshToken: response.refreshToken,
            refreshTokenExpiresAt: response.refreshTokenExpiresAt,
            userId: response.userId
        )
        try await apiClient.tokenStore.storeTokens(tokens)
        AppLogger.backend.info("Backend session established for Apple identity.")
    }

    /// Calls `POST /v1/auth/logout` (best effort) and clears local tokens.
    /// Network failures are logged but not propagated — the caller almost
    /// always wants to forget the session locally regardless.
    func logout() async {
        let tokens = await apiClient.tokenStore.currentTokens()
        if let tokens {
            do {
                try await apiClient.sendNoResponse(
                    method: .post,
                    path: "/v1/auth/logout",
                    body: LogoutRequest(refreshToken: tokens.refreshToken),
                    authenticated: false
                )
            } catch {
                AppLogger.backend.notice(
                    "Backend logout call failed (clearing tokens anyway): \(String(describing: error), privacy: .public)"
                )
            }
        }
        await apiClient.tokenStore.clearTokens()
    }

    /// Returns the userId baked into the cached token pair, or `nil` when
    /// the device has never completed the handshake.
    func currentUserId() async -> String? {
        await apiClient.tokenStore.currentTokens()?.userId
    }

    /// `true` when valid backend tokens are persisted on this device.
    func isAuthenticatedToBackend() async -> Bool {
        guard let tokens = await apiClient.tokenStore.currentTokens() else { return false }
        return !tokens.isRefreshTokenExpired
    }
}
