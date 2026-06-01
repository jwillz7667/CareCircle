import Foundation
import OSLog
import UIKit

// MARK: - RegisterDeviceRequest

/// Body for `POST /v1/me/devices`. Mirrors the backend `registerDeviceSchema`:
/// the APNs token is the only required field; the rest is best-effort device
/// metadata used for support and per-device push targeting.
nonisolated private struct RegisterDeviceRequest: Encodable, Sendable {
    let apnsToken: String
    let deviceName: String?
    let osVersion: String?
    let appVersion: String?
    let locale: String?
    let timezone: String?
}

// MARK: - PushRegistrationService

/// Owns APNs device-token registration. The OS delivers the token to the
/// `AppDelegate`, which forwards it here via `handleDeviceToken(_:)`; this
/// service hex-encodes it and `POST`s to `/v1/me/devices` so the backend can
/// target the device for SOS and reminder pushes.
///
/// The token can arrive before the user is signed in (the OS caches it across
/// launches). When that happens we buffer the hex and flush it once auth lands
/// via `flushPendingRegistration()`. Registration is idempotent server-side
/// (`ON CONFLICT (user_id, apns_token)`), so re-posting the same token is safe.
@MainActor
@Observable
final class PushRegistrationService {
    private let apiClient: APIClient
    private let isAuthenticated: () -> Bool

    private var pendingTokenHex: String?
    private var lastRegisteredTokenHex: String?

    init(apiClient: APIClient, isAuthenticated: @escaping () -> Bool) {
        self.apiClient = apiClient
        self.isAuthenticated = isAuthenticated
    }

    /// Asks iOS for an APNs device token. Safe to call without notification
    /// authorization — the token is still issued (authorization only gates
    /// whether alerts display). The token returns asynchronously through the
    /// AppDelegate. Call on launch-when-signed-in and on each sign-in.
    func registerForPushNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Forwarded from `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
    func handleDeviceToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard hex != lastRegisteredTokenHex else { return }
        guard isAuthenticated() else {
            pendingTokenHex = hex
            AppLogger.push.info("Buffered APNs token until sign-in.")
            return
        }
        Task { await register(tokenHex: hex) }
    }

    /// Forwarded from `AppDelegate.didFailToRegisterForRemoteNotificationsWithError`.
    /// Common on Simulator (no APNs) — logged, not surfaced to the user.
    func registrationDidFail(_ error: Error) {
        let described = String(describing: error)
        AppLogger.push.error("Remote notification registration failed: \(described, privacy: .public)")
    }

    /// Re-attempts a buffered registration. Call once sign-in completes.
    func flushPendingRegistration() {
        guard isAuthenticated(), let hex = pendingTokenHex else { return }
        pendingTokenHex = nil
        Task { await register(tokenHex: hex) }
    }

    private func register(tokenHex: String) async {
        let request = RegisterDeviceRequest(
            apnsToken: tokenHex,
            deviceName: UIDevice.current.name,
            osVersion: "iOS \(UIDevice.current.systemVersion)",
            appVersion: Self.appVersion,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        do {
            try await apiClient.sendNoResponse(method: .post, path: "/v1/me/devices", body: request)
            lastRegisteredTokenHex = tokenHex
            AppLogger.push.info("Registered APNs device token with backend.")
        } catch {
            // Keep the token buffered so a later trigger (re-launch, sign-in,
            // token refresh) retries the registration.
            pendingTokenHex = tokenHex
            let described = String(describing: error)
            AppLogger.push.error("Device registration failed: \(described, privacy: .public)")
        }
    }

    private static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
