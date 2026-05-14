import Foundation

// MARK: - ShiftDigestArtifactsSnapshot

/// Frozen snapshot of structured care events inside the shift window.
/// Encoded into `ShiftDigest.structuredArtifactsJSON` at compose time
/// so the digest detail view always shows what the caregiver was
/// narrating against, independent of later edits to source records.
nonisolated struct ShiftDigestArtifactsSnapshot: Codable, Sendable, Hashable {
    var doses: [DoseSnapshot] = []
    var appointments: [AppointmentSnapshot] = []
    var vitals: [VitalSnapshot] = []
    var journal: [JournalSnapshot] = []

    var isEmpty: Bool {
        doses.isEmpty && appointments.isEmpty && vitals.isEmpty && journal.isEmpty
    }

    func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> ShiftDigestArtifactsSnapshot? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShiftDigestArtifactsSnapshot.self, from: data)
    }
}

// MARK: - Nested snapshot types

extension ShiftDigestArtifactsSnapshot {
    nonisolated struct DoseSnapshot: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var medicationName: String
        var dosage: String?
        var scheduledAt: Date
        var takenAt: Date?
        var status: String
    }

    nonisolated struct AppointmentSnapshot: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var title: String
        var startsAt: Date
        var durationMinutes: Int
        var status: String?
    }

    nonisolated struct VitalSnapshot: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var kind: String
        var value: String
        var unit: String?
        var recordedAt: Date
    }

    nonisolated struct JournalSnapshot: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var mood: String?
        var summary: String
        var recordedAt: Date
    }
}
