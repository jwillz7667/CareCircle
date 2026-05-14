import Foundation
import SwiftData

// MARK: - ShiftDigest

/// End-of-shift narration left by the off-going caregiver for the next.
///
/// The caregiver records a 20–30s voice memo; the client transcribes,
/// runs entity extraction, and snapshots structured artifacts (doses,
/// appointments, vitals, journal entries) within the shift window. The
/// next caregiver opens the digest and sees a structured rollup +
/// transcript + audio + entity chips.
@Model
final class ShiftDigest {
    var id = UUID()
    var shiftStartAt = Date.now
    var shiftEndAt = Date.now
    var narratorAppleUserID = ""
    var narratorDisplayName = ""
    var transcript = ""
    var summary: String?

    @Attribute(.externalStorage)
    var audioData: Data?

    var audioDurationSeconds: Double = 0

    /// Encoded `ExtractedEntities`. Same encoding scheme as `Activity`
    /// so the entity-chip rendering pipeline is shared.
    var extractedEntitiesJSON: String?

    /// Encoded `ShiftDigestArtifactsSnapshot`. Captured at compose time —
    /// the digest is the historical record of what the caregiver was
    /// narrating against, even if the underlying doses/appointments later
    /// change.
    var structuredArtifactsJSON: String?

    var relatedShiftID: UUID?

    var createdAt = Date.now

    var circle: Circle?

    init(
        id: UUID = UUID(),
        shiftStartAt: Date,
        shiftEndAt: Date,
        narratorAppleUserID: String,
        narratorDisplayName: String,
        transcript: String = "",
        summary: String? = nil,
        audioData: Data? = nil,
        audioDurationSeconds: Double = 0,
        extractedEntitiesJSON: String? = nil,
        structuredArtifactsJSON: String? = nil,
        relatedShiftID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.shiftStartAt = shiftStartAt
        self.shiftEndAt = shiftEndAt
        self.narratorAppleUserID = narratorAppleUserID
        self.narratorDisplayName = narratorDisplayName
        self.transcript = transcript
        self.summary = summary
        self.audioData = audioData
        self.audioDurationSeconds = audioDurationSeconds
        self.extractedEntitiesJSON = extractedEntitiesJSON
        self.structuredArtifactsJSON = structuredArtifactsJSON
        self.relatedShiftID = relatedShiftID
        self.createdAt = createdAt
    }

    var extractedEntities: ExtractedEntities? {
        guard let json = extractedEntitiesJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExtractedEntities.self, from: data)
    }

    var structuredArtifacts: ShiftDigestArtifactsSnapshot? {
        guard let json = structuredArtifactsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ShiftDigestArtifactsSnapshot.self, from: data)
    }

    var durationSeconds: TimeInterval {
        max(0, shiftEndAt.timeIntervalSince(shiftStartAt))
    }
}
