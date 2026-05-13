import Foundation
import OSLog
import UserNotifications

// MARK: - SOSNotificationAuthorizer

/// Requests notification authorization for SOS surfaces. `.criticalAlert`
/// is entitlement-gated by Apple (granted case-by-case) — we ask for it
/// anyway so the alert escalates as soon as the entitlement lands without
/// a code change. When critical alert is denied, the SOS notification
/// still posts via `.timeSensitive`, which bypasses Focus modes but not
/// silent mode.
enum SOSNotificationAuthorizer {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        // `.timeSensitive` is no longer required as an option request on
        // current iOS — interruption level alone unlocks Focus bypass when
        // the time-sensitive entitlement is present.
        let options: UNAuthorizationOptions = [
            .alert,
            .sound,
            .criticalAlert,
        ]

        do {
            let granted = try await center.requestAuthorization(options: options)
            let settings = await center.notificationSettings()
            let critical = settings.criticalAlertSetting == .enabled
            AppLogger.sos.info(
                "Notification authorization granted=\(granted, privacy: .public) critical=\(critical, privacy: .public)"
            )
        } catch {
            let described = String(describing: error)
            AppLogger.sos.error(
                "Notification authorization failed: \(described, privacy: .public)"
            )
        }
    }
}
