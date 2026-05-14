import Foundation
import SwiftData

// MARK: - JournalEntry

/// Once-a-day "how is the Care Recipient doing today" log entry. One
/// entry per Circle per local day — `recordedAt` is normalised to
/// `Calendar.current.startOfDay` so dedupe by date works without
/// timezone surprises.
///
/// Filled by any caregiver in the Circle. Authorship is snapshotted so
/// "Mom logged her own mood" vs "Bob filled this in" remains visible
/// after a member is removed.
@Model
final class JournalEntry {
    var id = UUID()
    var circle: Circle?

    /// Calendar-day timestamp (start-of-day) the entry refers to. Use
    /// this as the dedupe + display key — `createdAt` covers "when did
    /// someone log it" for audit purposes only.
    var recordedAt = Date.now
    var createdAt = Date.now
    var editedAt: Date?

    var moodRaw = Mood.neutral.rawValue
    var symptomsRaw = ""
    var notes = ""

    var authorAppleUserID = ""
    var authorDisplayName = ""

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }

    var symptoms: [SymptomTag] {
        get {
            symptomsRaw
                .split(separator: ",")
                .compactMap { SymptomTag(rawValue: String($0)) }
        }
        set {
            symptomsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        mood: Mood,
        symptoms: [SymptomTag],
        notes: String,
        authorAppleUserID: String,
        authorDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.recordedAt = Calendar.current.startOfDay(for: recordedAt)
        moodRaw = mood.rawValue
        symptomsRaw = symptoms.map(\.rawValue).joined(separator: ",")
        self.notes = notes
        self.authorAppleUserID = authorAppleUserID
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
    }
}
