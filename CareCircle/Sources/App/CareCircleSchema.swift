import SwiftData

// MARK: - Versioned schema

/// The current persisted schema, versioned so future model changes have an
/// explicit, audited migration home instead of relying on SwiftData's silent
/// inference. The CloudKit-backed store supports only *lightweight*
/// migrations (CloudKit syncs asynchronously across devices, so custom
/// migration stages can't run safely), so each future change appends a new
/// `VersionedSchema` and a `MigrationStage.lightweight(fromVersion:toVersion:)`
/// in `CareCircleMigrationPlan` rather than mutating this one.
///
/// Keep `models` in lockstep with `LocalStoreEraser`'s delete list.
enum CareCircleSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Circle.self,
            CareRecipient.self,
            Member.self,
            Activity.self,
            ActivityReaction.self,
            ActivityComment.self,
            Medication.self,
            DoseEvent.self,
            Appointment.self,
            Document.self,
            SOSEvent.self,
            EmergencyContact.self,
            CareMinuteEntry.self,
            ShiftDigest.self,
            Insight.self,
            Vital.self,
            LocationSnapshot.self,
            HealthRecord.self,
            JournalEntry.self,
            PendingOperation.self,
        ]
    }
}

// MARK: - Migration plan

/// Drives schema evolution for the CloudKit-backed store. It currently pins
/// the single shipped version; the next model change appends a
/// `CareCircleSchemaV2` to `schemas` and a
/// `MigrationStage.lightweight(fromVersion: CareCircleSchemaV1.self,
/// toVersion: CareCircleSchemaV2.self)` to `stages`.
enum CareCircleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CareCircleSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
