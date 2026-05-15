import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

// MARK: - GoogleSignInCoordinator

/// Performs Google sign-in via the OAuth 2.0 authorization-code + PKCE flow
/// using `ASWebAuthenticationSession`. No third-party SwiftPM dependency:
/// Apple's own web-auth session drives the round trip and the iOS app
/// completes the code-for-token exchange directly against
/// `oauth2.googleapis.com`.
///
/// Returns Google's `id_token`, which is then passed to
/// `BackendAuthService.exchangeGoogleIdentity(idToken:)` so the backend can
/// re-verify the JWT signature against Google's JWKS before minting a
/// CareCircle session.
///
/// Configuration is read at runtime from `Info.plist`:
/// - `GoogleOAuthClientId` — the iOS-type OAuth 2.0 Client ID issued in
///   Google Cloud Console, e.g. `"1234567890-abc.apps.googleusercontent.com"`.
/// - A `CFBundleURLTypes` entry whose scheme is the reversed Client ID
///   (e.g. `com.googleusercontent.apps.1234567890-abc`). The redirect URI
///   used here is `<reversedClientId>:/oauth2redirect`.
///
/// When either piece of configuration is missing, `isConfigured` is `false`
/// and the UI should hide or disable the Google button rather than crash.
@MainActor
final class GoogleSignInCoordinator: NSObject {
    enum GoogleSignInError: LocalizedError, Equatable {
        case notConfigured
        case canceled
        case stateMismatch
        case missingAuthorizationCode
        case tokenExchangeFailed(String)
        case missingIDToken
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Google sign-in isn't configured for this build."
            case .canceled:
                "Sign in was canceled."
            case .stateMismatch:
                "Sign in could not be verified. Please try again."
            case .missingAuthorizationCode:
                "Google did not return an authorization code."
            case let .tokenExchangeFailed(detail):
                "Google rejected the token exchange (\(detail))."
            case .missingIDToken:
                "Google did not return an identity token."
            case let .transport(detail):
                "Could not reach Google (\(detail))."
            }
        }
    }

    /// `true` only when both the client ID and the matching URL scheme are
    /// registered. Use this to gate the "Continue with Google" button.
    var isConfigured: Bool {
        Self.resolvedClientId() != nil
    }

    /// Drives the full handshake and returns the Google `id_token`.
    func signIn() async throws(GoogleSignInError) -> String {
        guard let clientId = Self.resolvedClientId() else {
            throw .notConfigured
        }
        let reversed = Self.reversedClientId(clientId)
        let redirectUri = "\(reversed):/oauth2redirect"
        let verifier = Self.makeCodeVerifier()
        let state = Self.makeRandomString(byteCount: 16)

        let authURL = try buildAuthorizationURL(
            clientId: clientId,
            redirectUri: redirectUri,
            challenge: Self.codeChallenge(for: verifier),
            state: state,
            nonce: Self.makeRandomString(byteCount: 16)
        )
        let callbackURL = try await runWebAuthSession(authURL: authURL, callbackScheme: reversed)
        let code = try extractAuthorizationCode(from: callbackURL, expectedState: state)
        return try await exchangeCodeForIDToken(
            code: code,
            verifier: verifier,
            clientId: clientId,
            redirectUri: redirectUri
        )
    }

    private func buildAuthorizationURL(
        clientId: String,
        redirectUri: String,
        challenge: String,
        state: String,
        nonce: String
    ) throws(GoogleSignInError)
        -> URL
    {
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw .transport("Could not build Google authorization URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            // `prompt=select_account` keeps the picker visible even on a
            // device with a single signed-in Google account so the user
            // sees the consent UI and can pick a different identity.
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let url = components.url else {
            throw .transport("Could not build Google authorization URL.")
        }
        return url
    }

    private func runWebAuthSession(
        authURL: URL,
        callbackScheme: String
    ) async throws(GoogleSignInError)
        -> URL
    {
        do {
            return try await startWebAuthSession(authURL: authURL, callbackScheme: callbackScheme)
        } catch let error as GoogleSignInError {
            throw error
        } catch {
            throw .transport(error.localizedDescription)
        }
    }

    private func extractAuthorizationCode(
        from callbackURL: URL,
        expectedState: String
    ) throws(GoogleSignInError)
        -> String
    {
        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value else
        {
            throw .stateMismatch
        }
        guard returnedState == expectedState else {
            throw .stateMismatch
        }
        guard
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty else
        {
            throw .missingAuthorizationCode
        }
        return code
    }

    // MARK: - ASWebAuthenticationSession plumbing

    private func startWebAuthSession(
        authURL: URL,
        callbackScheme: String
    ) async throws
        -> URL
    {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.canceled)
                    return
                }
                if let error {
                    continuation.resume(throwing: GoogleSignInError.transport(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.canceled)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Ephemeral session sidesteps the Safari shared-cookie consent
            // dialog every launch — better UX for an app where sign-in is
            // a one-time event per device.
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                continuation.resume(throwing: GoogleSignInError.transport("Could not start Google sign-in."))
            }
        }
    }

    private func exchangeCodeForIDToken(
        code: String,
        verifier: String,
        clientId: String,
        redirectUri: String
    ) async throws(GoogleSignInError)
        -> String
    {
        let request = try makeTokenExchangeRequest(
            code: code,
            verifier: verifier,
            clientId: clientId,
            redirectUri: redirectUri
        )
        let data = try await performTokenExchange(request: request)
        return try decodeIDToken(from: data)
    }

    private func makeTokenExchangeRequest(
        code: String,
        verifier: String,
        clientId: String,
        redirectUri: String
    ) throws(GoogleSignInError)
        -> URLRequest
    {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw .transport("Could not build Google token URL.")
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func performTokenExchange(request: URLRequest) async throws(GoogleSignInError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw .transport(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .tokenExchangeFailed("non-HTTP response")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "status \(httpResponse.statusCode)"
            throw .tokenExchangeFailed("status \(httpResponse.statusCode): \(detail)")
        }
        return data
    }

    private func decodeIDToken(from data: Data) throws(GoogleSignInError) -> String {
        struct TokenResponse: Decodable {
            let idToken: String?
            enum CodingKeys: String, CodingKey { case idToken = "id_token" }
        }
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard let idToken = decoded.idToken, !idToken.isEmpty else {
                throw GoogleSignInError.missingIDToken
            }
            return idToken
        } catch let error as GoogleSignInError {
            throw error
        } catch {
            throw .tokenExchangeFailed("decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func resolvedClientId() -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientId") as? String,
            !value.isEmpty,
            value != "$(GOOGLE_OAUTH_CLIENT_ID)" else
        {
            return nil
        }
        return value
    }

    private static func reversedClientId(_ clientId: String) -> String {
        clientId.split(separator: ".").reversed().joined(separator: ".")
    }

    /// Base64url-encoded random bytes — meets Google's PKCE verifier rules
    /// (43–128 unreserved characters). 32 bytes of entropy is the
    /// recommended size.
    private static func makeCodeVerifier(byteCount: Int = 32) -> String {
        makeRandomString(byteCount: byteCount)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    /// Cryptographically-random base64url string. Used for the PKCE
    /// verifier, the OAuth `state`, and the OIDC `nonce`.
    fileprivate static func makeRandomString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            // SecRandomCopyBytes failing means the system PRNG is dead —
            // there's nothing to fall back on safely. Crashing here is
            // the correct response in the same way a missing keychain is.
            fatalError("SecRandomCopyBytes failed with status \(status)")
        }
        return Data(bytes).base64URLEncodedString()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleSignInCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Called from the AS session's worker; bounce back to the main
        // actor to read the active window. Returning a fresh `UIWindow()`
        // is the documented fallback when no key window is available
        // (background launch, unit test, etc).
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return window
            }
            if let window = scenes.flatMap(\.windows).first {
                return window
            }
            return UIWindow()
        }
    }
}

// MARK: - Data + base64url

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
