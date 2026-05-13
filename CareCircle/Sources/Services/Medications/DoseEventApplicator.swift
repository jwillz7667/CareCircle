import Foundation
import SwiftData

// MARK: - DoseEventApplicator

/// Idempotent helper that finds or creates a DoseEvent for a (medication,
/// scheduledAt) pair and mutates its status. Used by both the in-app
/// "Mark taken" buttons and the notification action handler.
@MainActor
enum DoseEventApplicator {
    nonisolated struct Marker: Sendable {
        var appleUserID: String
        var displayName: String
    }

    @discardableResult
    static func apply(
        status: DoseStatus,
        scheduledAt: Date,
        medication: Medication,
        in context: ModelContext,
        marker: Marker?
    )
        -> DoseEvent
    {
        let medicationID = medication.id
        let descriptor = FetchDescriptor<DoseEvent>(
            predicate: #Predicate { event in
                event.medication?.id == medicationID
                    && event.scheduledAt == scheduledAt
            }
        )
        let existing = try? context.fetch(descriptor).first
        let event = existing ?? DoseEvent(
            scheduledAt: scheduledAt,
            status: status,
            markedByAppleUserID: marker?.appleUserID,
            markedByDisplayName: marker?.displayName
        )
        event.medication = medication
        event.status = status
        event.markedByAppleUserID = marker?.appleUserID ?? event.markedByAppleUserID
        event.markedByDisplayName = marker?.displayName ?? event.markedByDisplayName
        event.updatedAt = .now
        switch status {
        case .taken, .late:
            event.takenAt = Date()
        case .skipped, .scheduled, .missed:
            event.takenAt = nil
        }
        if existing == nil {
            context.insert(event)
        }
        if let circle = medication.circle {
            postFeedEntry(for: status, medication: medication, circle: circle, marker: marker, in: context)
        }
        return event
    }

    private static func postFeedEntry(
        for status: DoseStatus,
        medication: Medication,
        circle: Circle,
        marker: Marker?,
        in context: ModelContext
    ) {
        let activityType: ActivityType
        let bodyVerb: String
        switch status {
        case .taken, .late:
            activityType = .medTaken
            bodyVerb = "Marked taken"
        case .skipped:
            activityType = .medTaken
            bodyVerb = "Marked skipped"
        case .missed, .scheduled:
            return
        }
        let activity = Activity(
            authorAppleUserID: marker?.appleUserID ?? "",
            authorDisplayName: marker?.displayName ?? "Reminder",
            type: activityType,
            body: "\(bodyVerb): \(medication.name) \(medication.dosage)".trimmingCharacters(in: .whitespaces)
        )
        activity.circle = circle
        context.insert(activity)
    }
}
