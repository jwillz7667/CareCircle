import CloudKit
import Foundation

// MARK: - CloudKitConfiguration

/// Single source of truth for CloudKit identifiers and zone naming.
nonisolated enum CloudKitConfiguration {
    /// Container identifier from `CareCircle.entitlements`.
    static let containerIdentifier = "iCloud.Res.CareCircle"

    /// Per-circle zone name. CKShares require a custom zone — the default zone cannot host shares.
    static func zoneName(for circleID: UUID) -> String {
        "circle-\(circleID.uuidString.lowercased())"
    }

    static func recordZoneID(for circleID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: circleID), ownerName: CKCurrentUserDefaultName)
    }

    static let circleRecordType = "Circle"

    /// Notification posted by `CircleSceneDelegate` when an inbound share acceptance completes.
    static let shareAcceptedNotification = Notification.Name("Res.CareCircle.shareAccepted")
}
