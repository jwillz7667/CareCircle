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

    /// CKRecord type that carries the per-circle document DEK across
    /// share participants. One per circle, in the per-circle zone.
    /// The DEK rides on `encryptedValues["dek"]` so CloudKit applies
    /// end-to-end encryption on top of the share's access controls.
    static let dekEnvelopeRecordType = "DocumentKeyEnvelope"

    /// Predictable record name for the DEK envelope so members can
    /// fetch it without enumerating the zone.
    static let dekEnvelopeRecordName = "dek-envelope"

    static func dekEnvelopeRecordID(for circleID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: dekEnvelopeRecordName, zoneID: recordZoneID(for: circleID))
    }

    /// Notification posted by `CircleSceneDelegate` when an inbound share acceptance completes.
    static let shareAcceptedNotification = Notification.Name("Res.CareCircle.shareAccepted")
}
