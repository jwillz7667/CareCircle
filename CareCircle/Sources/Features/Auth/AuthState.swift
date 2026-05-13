import AuthenticationServices
import Foundation
import OSLog

// MARK: - AuthState

@Observable
@MainActor
final class AuthState {
    private(set) var status: AuthStatus = .unknown
    private(set) var lastError: AuthError?

    private let keychain: KeychainStore
    private let credentialProvider: ASAuthorizationAppleIDProvider
    private let backendAuthService: BackendAuthService
    private let syncEngine: SyncEngine

    init(
        backendAuthService: BackendAuthService,
        syncEngine: SyncEngine,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.backendAuthService = backendAuthService
        self.syncEngine = syncEngine
        self.keychain = keychain
        credentialProvider = ASAuthorizationAppleIDProvider()
    }

    func bootstrap() async {
        guard let stored = loadStoredUser() else {
            status = .signedOut
            return
        }

        let state = await credentialState(for: stored.id)
        switch state {
        case .authorized:
            status = .signedIn(stored)
            syncEngine.refreshPendingCount()
            syncEngine.triggerDrain()
        case .revoked, .notFound, .transferred:
            AppLogger.auth
                .notice(
                    "Apple credential no longer valid (state=\(state.rawValue, privacy: .public)); clearing local user."
                )
            clearStoredUser()
            await backendAuthService.logout()
            status = .signedOut
        @unknown default:
            AppLogger.auth
                .error("Unknown ASAuthorizationAppleIDProvider credential state: \(state.rawValue, privacy: .public)")
            status = .signedOut
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
        Task { await backendAuthService.logout() }
        AppLogger.auth.info("User signed out.")
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
            givenName: givenName,
            familyName: familyName,
            email: email
        )
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
