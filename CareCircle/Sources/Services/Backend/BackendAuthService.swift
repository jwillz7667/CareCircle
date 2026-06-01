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

    /// Registers a new email-auth account and persists the resulting
    /// session. Backend rejects (409) when the email is already claimed
    /// by any provider — the caller should surface that as a "use your
    /// existing sign-in method" error rather than letting it look like a
    /// generic network failure.
    func registerWithEmail(
        email: String,
        password: String,
        displayName: String?
    ) async throws(APIError) {
        let request = EmailRegisterRequest(
            email: email,
            password: password,
            displayName: displayName
        )
        let response: BackendAuthResponse = try await apiClient.send(
            method: .post,
            path: "/v1/auth/register",
            body: request,
            authenticated: false
        )
        try await persist(response: response, logLabel: "email registration")
    }

    /// Signs in an existing email-auth account. Backend returns a
    /// deliberately generic 401 for both wrong-password and unknown-email
    /// so the UI must do the same — don't leak which half failed.
    func signInWithEmail(
        email: String,
        password: String
    ) async throws(APIError) {
        let request = EmailLoginRequest(email: email, password: password)
        let response: BackendAuthResponse = try await apiClient.send(
            method: .post,
            path: "/v1/auth/login",
            body: request,
            authenticated: false
        )
        try await persist(response: response, logLabel: "email sign-in")
    }

    /// Exchanges a Google-issued ID token for a backend session. The token
    /// must originate from the PKCE OAuth handshake the iOS app performs
    /// against `accounts.google.com` — the backend re-verifies the JWT
    /// signature against Google's JWKS, the `aud` claim, and `email_verified`.
    func exchangeGoogleIdentity(idToken: String) async throws(APIError) {
        let request = GoogleAuthRequest(idToken: idToken)
        let response: BackendAuthResponse = try await apiClient.send(
            method: .post,
            path: "/v1/auth/google",
            body: request,
            authenticated: false
        )
        try await persist(response: response, logLabel: "Google sign-in")
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

    /// `GET /v1/me`. Used as a lightweight session proof-of-life — the
    /// backend will refuse with 401 if the access token is dead, which
    /// gives the UI a concrete signal that the session is healthy beyond
    /// "we still have a token on disk."
    func fetchMe() async throws(APIError) -> BackendUserProfile {
        try await apiClient.send(
            method: .get,
            path: "/v1/me",
            authenticated: true
        )
    }

    /// `DELETE /v1/me`. Soft-deletes the account server-side (the backend
    /// then runs the cascading teardown — owned circles, members, devices,
    /// PII scrub, object purge — out-of-band) and forgets the local token
    /// pair. The session is unrecoverable afterwards.
    func deleteAccount() async throws(APIError) {
        try await apiClient.sendNoResponse(method: .delete, path: "/v1/me", authenticated: true)
        await apiClient.tokenStore.clearTokens()
        AppLogger.backend.info("Backend account deleted; local tokens cleared.")
    }

    /// `POST /v1/me/export`. Returns the raw ZIP archive of the caller's
    /// data (profile + per-circle decrypted records) for the user to keep.
    func exportData() async throws(APIError) -> Data {
        try await apiClient.sendForData(method: .post, path: "/v1/me/export", authenticated: true)
    }

    /// `true` when valid backend tokens are persisted on this device.
    func isAuthenticatedToBackend() async -> Bool {
        guard let tokens = await apiClient.tokenStore.currentTokens() else { return false }
        return !tokens.isRefreshTokenExpired
    }

    private func persist(response: BackendAuthResponse, logLabel: StaticString) async throws(APIError) {
        let tokens = BackendTokens(
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshToken: response.refreshToken,
            refreshTokenExpiresAt: response.refreshTokenExpiresAt,
            userId: response.userId
        )
        try await apiClient.tokenStore.storeTokens(tokens)
        AppLogger.backend.info("Backend session established (\(logLabel)).")
    }
}
