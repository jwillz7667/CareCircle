import Foundation
import OSLog
import SwiftData

// MARK: - LocalStoreEraser

/// Wipes every CareCircle model from the local SwiftData store. Invoked on
/// account deletion so no on-device data — nor anything mirrored into the
/// user's private CloudKit database — outlives the account.
///
/// The type list mirrors the schema in `CareCircleApp.makeModelContainer`;
/// keep the two in lockstep when models are added or removed.
enum LocalStoreEraser {
    /// Erases all model rows and forgets every per-circle document key.
    ///
    /// Per-circle AES keys live in the Keychain under
    /// `AccessibleAfterFirstUnlockThisDeviceOnly`, which — like the cached
    /// auth credentials `CareCircleApp` purges on fresh install — survives
    /// an app uninstall. Account deletion must drop them too, otherwise a
    /// reinstall could still decrypt CloudKit-cached ciphertext. We read the
    /// circle IDs before deleting the rows, then forget each key.
    ///
    /// (A future per-member "leave circle" flow should call
    /// `keyStore.forget(circleID:)` for just that circle on the same basis.)
    static func eraseAll(
        in context: ModelContext,
        keyStore: DocumentKeyStore = .shared
    ) throws {
        let circleIDs = (try? context.fetch(FetchDescriptor<Circle>()))?.map(\.id) ?? []

        try context.delete(model: Circle.self)
        try context.delete(model: CareRecipient.self)
        try context.delete(model: Member.self)
        try context.delete(model: Activity.self)
        try context.delete(model: ActivityReaction.self)
        try context.delete(model: ActivityComment.self)
        try context.delete(model: Medication.self)
        try context.delete(model: DoseEvent.self)
        try context.delete(model: Appointment.self)
        try context.delete(model: Document.self)
        try context.delete(model: SOSEvent.self)
        try context.delete(model: EmergencyContact.self)
        try context.delete(model: CareMinuteEntry.self)
        try context.delete(model: ShiftDigest.self)
        try context.delete(model: Insight.self)
        try context.delete(model: Vital.self)
        try context.delete(model: LocationSnapshot.self)
        try context.delete(model: HealthRecord.self)
        try context.delete(model: JournalEntry.self)
        try context.delete(model: PendingOperation.self)
        try context.save()

        // Best-effort: the rows are already gone, so a Keychain delete
        // failure shouldn't fail the whole account deletion — log and move on.
        for circleID in circleIDs {
            do {
                try keyStore.forget(circleID: circleID)
            } catch {
                AppLogger.persistence.error(
                    "Failed to forget document key on account erase: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
