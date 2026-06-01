import SwiftData

// MARK: - LocalStoreEraser

/// Wipes every CareCircle model from the local SwiftData store. Invoked on
/// account deletion so no on-device data — nor anything mirrored into the
/// user's private CloudKit database — outlives the account.
///
/// The type list mirrors the schema in `CareCircleApp.makeModelContainer`;
/// keep the two in lockstep when models are added or removed.
enum LocalStoreEraser {
    static func eraseAll(in context: ModelContext) throws {
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
        try context.delete(model: ChatMessage.self)
        try context.delete(model: HealthRecord.self)
        try context.delete(model: DirectThread.self)
        try context.delete(model: DirectMessage.self)
        try context.delete(model: JournalEntry.self)
        try context.delete(model: PendingOperation.self)
        try context.save()
    }
}
