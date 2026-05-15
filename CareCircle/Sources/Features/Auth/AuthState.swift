import AuthenticationServices
import Foundation
import OSLog

// MARK: - AuthState

@Observable
@MainActor
final class AuthState {
    private(set) var status: AuthStatus = .unknown
    private(set) var lastError: AuthError?
    private(set) var lastVerifiedProfile: BackendUserProfile?
    private(set) var lastVerifyError: APIError?

    private let keychain: KeychainStore
    private let credentialProvider: ASAuthorizationAppleIDProvider
    private let backendAuthService: BackendAuthService
    private let syncEngine: SyncEngine
    private let googleCoordinator: GoogleSignInCoordinator

    init(
        backendAuthService: BackendAuthService,
        syncEngine: SyncEngine,
        keychain: KeychainStore = KeychainStore(),
        googleCoordinator: GoogleSignInCoordinator? = nil
    ) {
        self.backendAuthService = backendAuthService
        self.syncEngine = syncEngine
        self.keychain = keychain
        self.googleCoordinator = googleCoordinator ?? GoogleSignInCoordinator()
        credentialProvider = ASAuthorizationAppleIDProvider()
    }

    /// Whether the build can present the "Continue with Google" button.
    /// Mirrors `GoogleSignInCoordinator.isConfigured`.
    var canSignInWithGoogle: Bool {
        googleCoordinator.isConfigured
    }

    func bootstrap() async {
        guard let stored = loadStoredUser() else {
            status = .signedOut
            return
        }

        switch stored.provider {
        case .apple:
            await bootstrapApple(stored: stored)
        case .email, .google:
            await bootstrapBackendOnly(stored: stored)
        }
    }

    private func bootstrapApple(stored: SignedInUser) async {
        // Legacy sessions store the Apple user ID in `id`; new sessions
        // store it on `appleUserId`. Fall back to `id` for compatibility.
        let appleUserID = stored.appleUserId ?? stored.id
        let state = await credentialState(for: appleUserID)
        switch state {
        case .authorized:
            status = .signedIn(stored)
            syncEngine.refreshPendingCount()
            syncEngine.triggerDrain()
            await verifyBackendSession()
        case .revoked, .notFound, .transferred:
            AppLogger.auth
                .notice(
                    "Apple credential no longer valid (state=\(state.rawValue, privacy: .public)); clearing local user."
                )
            clearStoredUser()
            await backendAuthService.logout()
            lastVerifiedProfile = nil
            lastVerifyError = nil
            status = .signedOut
        @unknown default:
            AppLogger.auth
                .error("Unknown ASAuthorizationAppleIDProvider credential state: \(state.rawValue, privacy: .public)")
            status = .signedOut
        }
    }

    private func bootstrapBackendOnly(stored: SignedInUser) async {
        // Email / Google sessions have no OS-level credential to consult.
        // Trust the keychain entry, then probe the backend to confirm the
        // refresh token still resolves.
        guard await backendAuthService.isAuthenticatedToBackend() else {
            clearStoredUser()
            await backendAuthService.logout()
            status = .signedOut
            return
        }
        status = .signedIn(stored)
        syncEngine.refreshPendingCount()
        syncEngine.triggerDrain()
        await verifyBackendSession()
    }

    /// Pings `GET /v1/me` to confirm the backend recognizes the cached
    /// session. Caches the response on `lastVerifiedProfile`; failure
    /// clears the cached profile and stores the error for the UI to show.
    /// Never throws — backend outages should not crash or sign the user out.
    func verifyBackendSession() async {
        guard await backendAuthService.isAuthenticatedToBackend() else {
            lastVerifiedProfile = nil
            lastVerifyError = nil
            return
        }
        do {
            let profile = try await backendAuthService.fetchMe()
            lastVerifiedProfile = profile
            lastVerifyError = nil
        } catch {
            lastVerifiedProfile = nil
            lastVerifyError = error
            AppLogger.backend.notice(
                "Session verification failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func completeAppleSignIn(
        result: Result<ASAuthorization, Error>,
        hashedNonce: String
    ) async {
        switch result {
        case let .success(authorization):
            do {
                let user = try makeUser(from: authorization, hashedNonce: hashedNonce)
                try persist(user)
                status = .signedIn(user)
                lastError = nil
                AppLogger.auth
                    .info("Apple sign-in complete for user id prefix \(String(user.id.prefix(6)), privacy: .public)")
                await exchangeBackendSession(authorization: authorization, hashedNonce: hashedNonce)
            } catch {
                lastError = error
                AppLogger.auth.error("Apple sign-in failed: \(String(describing: error), privacy: .public)")
            }
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                lastError = .canceled
            } else {
                lastError = .unknown(error.localizedDescription)
            }
            AppLogger.auth.notice("Apple sign-in failure: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() {
        clearStoredUser()
        status = .signedOut
        lastError = nil
        lastVerifiedProfile = nil
        lastVerifyError = nil
        Task { await backendAuthService.logout() }
        AppLogger.auth.info("User signed out.")
    }

    /// Clears the surfaced error so a previous failure does not bleed into
    /// a fresh form submission (e.g. flipping between sign-in and create).
    func clearLastError() {
        lastError = nil
    }

    private func exchangeBackendSession(
        authorization: ASAuthorization,
        hashedNonce: String
    ) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8) else
        {
            AppLogger.auth.error("Apple credential missing identity token; skipping backend exchange.")
            return
        }

        do {
            try await backendAuthService.exchangeAppleIdentity(
                identityToken: identityToken,
                nonce: hashedNonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
            syncEngine.refreshPendingCount()
            syncEngine.triggerDrain()
            await verifyBackendSession()
        } catch {
            // Local Apple session is still valid; only the backend leg failed.
            // The user keeps CloudKit functionality and the next foreground
            // attempt can retry.
            AppLogger.auth.error(
                "Backend exchange failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func credentialState(for userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            credentialProvider.getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    private func makeUser(from auth: ASAuthorization, hashedNonce: String) throws(AuthError) -> SignedInUser {
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            throw .invalidCredential
        }

        // The SHA-256 hashed nonce is forwarded to the backend so the
        // server-side identity-token verifier can compare it against the
        // JWT's `nonce` claim. Locally we only require the hash to exist.
        guard !hashedNonce.isEmpty else {
            throw .nonceMismatch
        }

        let existing = loadStoredUser()

        // Apple only returns name/email on first sign-in; preserve previous values on subsequent ones.
        let givenName = credential.fullName?.givenName ?? existing?.givenName
        let familyName = credential.fullName?.familyName ?? existing?.familyName
        let email = credential.email ?? existing?.email

        return SignedInUser(
            id: credential.user,
            provider: .apple,
            givenName: givenName,
            familyName: familyName,
            email: email,
            appleUserId: credential.user
        )
    }

    // MARK: - Email sign-in

    func registerWithEmail(
        email: String,
        password: String,
        displayName: String?
    ) async {
        await runEmailFlow(label: "register") {
            try await backendAuthService.registerWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
        } finalize: { userId in
            SignedInUser(
                id: userId,
                provider: .email,
                givenName: displayName,
                familyName: nil,
                email: email,
                appleUserId: nil
            )
        }
    }

    func signInWithEmail(
        email: String,
        password: String
    ) async {
        await runEmailFlow(label: "login") {
            try await backendAuthService.signInWithEmail(
                email: email,
                password: password
            )
        } finalize: { userId in
            SignedInUser(
                id: userId,
                provider: .email,
                givenName: nil,
                familyName: nil,
                email: email,
                appleUserId: nil
            )
        }
    }

    private func runEmailFlow(
        label: StaticString,
        attempt: () async throws -> Void,
        finalize: (String) -> SignedInUser
    ) async {
        lastError = nil
        do {
            try await attempt()
        } catch let apiError as APIError {
            lastError = mapEmailError(apiError)
            AppLogger.auth.notice(
                "Email \(label, privacy: .public) failed: \(String(describing: apiError), privacy: .public)"
            )
            return
        } catch {
            // BackendAuthService's email methods declare `throws(APIError)`,
            // so this branch is unreachable in practice; keep it to satisfy
            // the type checker when typed-throws inference can't propagate
            // through the trailing closure.
            lastError = .unknown(error.localizedDescription)
            AppLogger.auth.error(
                "Unexpected error during email \(label, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard let userId = await backendAuthService.currentUserId() else {
            // Backend returned a token pair but no userId — treat as a
            // backend bug rather than crashing.
            lastError = .backendUnavailable
            await backendAuthService.logout()
            return
        }

        let user = finalize(userId)
        do {
            try persist(user)
            status = .signedIn(user)
            syncEngine.refreshPendingCount()
            syncEngine.triggerDrain()
            await verifyBackendSession()
            AppLogger.auth
                .info(
                    "Email \(label, privacy: .public) complete for user id prefix \(String(user.id.prefix(6)), privacy: .public)"
                )
        } catch {
            lastError = error
            await backendAuthService.logout()
            AppLogger.auth.error(
                "Failed to persist email session locally: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Google sign-in

    /// Drives the iOS Google sign-in handshake (ASWebAuthenticationSession
    /// + PKCE), exchanges the resulting ID token for a CareCircle session,
    /// and persists the result locally. The UI should only call this when
    /// `canSignInWithGoogle` is `true`.
    func signInWithGoogle() async {
        lastError = nil
        let idToken: String
        do {
            idToken = try await googleCoordinator.signIn()
        } catch GoogleSignInCoordinator.GoogleSignInError.canceled {
            lastError = .canceled
            return
        } catch GoogleSignInCoordinator.GoogleSignInError.notConfigured {
            lastError = .googleSignInUnavailable
            return
        } catch {
            lastError = .googleSignInFailed(error.localizedDescription)
            AppLogger.auth.error(
                "Google sign-in failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        do {
            try await backendAuthService.exchangeGoogleIdentity(idToken: idToken)
        } catch {
            lastError = mapEmailError(error)
            AppLogger.auth.notice(
                "Google backend exchange failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard let userId = await backendAuthService.currentUserId() else {
            lastError = .backendUnavailable
            await backendAuthService.logout()
            return
        }

        let user = SignedInUser(
            id: userId,
            provider: .google,
            givenName: nil,
            familyName: nil,
            email: nil,
            appleUserId: nil
        )
        do {
            try persist(user)
            status = .signedIn(user)
            syncEngine.refreshPendingCount()
            syncEngine.triggerDrain()
            await verifyBackendSession()
            AppLogger.auth
                .info("Google sign-in complete for user id prefix \(String(user.id.prefix(6)), privacy: .public)")
        } catch {
            lastError = error
            await backendAuthService.logout()
            AppLogger.auth.error(
                "Failed to persist Google session locally: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func mapEmailError(_ error: APIError) -> AuthError {
        switch error {
        case let .http(status, _):
            switch status {
            case 401: .invalidEmailOrPassword
            case 409: .emailAlreadyInUse
            case 400: .unknown("Please check your email and password.")
            default: .unknown(error.localizedDescription)
            }
        case .transport:
            .backendUnavailable
        default:
            .unknown(error.localizedDescription)
        }
    }

    private func persist(_ user: SignedInUser) throws(AuthError) {
        do {
            let data = try JSONEncoder().encode(user)
            try keychain.set(data, forKey: KeychainStore.signedInUserKey)
        } catch let error as KeychainError {
            if case let .unhandled(status) = error {
                throw .keychainFailure(status)
            }
            throw .keychainFailure(errSecInternalError)
        } catch {
            throw .unknown(error.localizedDescription)
        }
    }

    private func loadStoredUser() -> SignedInUser? {
        do {
            guard let data = try keychain.data(forKey: KeychainStore.signedInUserKey) else {
                return nil
            }
            return try JSONDecoder().decode(SignedInUser.self, from: data)
        } catch {
            AppLogger.auth
                .error("Failed to load stored user from keychain: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func clearStoredUser() {
        do {
            try keychain.delete(KeychainStore.signedInUserKey)
        } catch {
            AppLogger.auth.error("Failed to delete stored user: \(String(describing: error), privacy: .public)")
        }
    }
}
