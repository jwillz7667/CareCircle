import Foundation

// MARK: - SyncOperationType

/// Stable string identifiers used as `operationType` on `POST /v1/sync/batch`.
/// Snake-case matches the convention the backend's sync tests already
/// exercise and the column values the eventual worker will switch on.
enum SyncOperationType {
    static let createActivity = "create_activity"
    static let createMedication = "create_medication"
    static let markDoseTaken = "mark_dose_taken"
    static let markDoseSkipped = "mark_dose_skipped"
    static let createAppointment = "create_appointment"
    static let createMember = "create_member"
    static let createEmergencyContact = "create_emergency_contact"
    static let createCareMinuteEntry = "create_care_minute_entry"
    static let createSOSEvent = "create_sos_event"
    static let createShiftDigest = "create_shift_digest"
}

// MARK: - Activity

/// Photo/audio attachments are intentionally omitted in this slice —
/// those require an upload-then-reference flow against MinIO and ship
/// in a later phase.
nonisolated struct CreateActivityPayload: Codable, Sendable, Equatable {
    let activityId: UUID
    let type: String
    let body: String
    let createdAt: Date
    let authorAppleUserID: String
    let authorDisplayName: String
    let audioDurationSeconds: Double
    let extractedEntitiesJSON: String?
}

// MARK: - Medications

nonisolated struct CreateMedicationPayload: Codable, Sendable, Equatable {
    let medicationId: UUID
    let name: String
    let dosage: String
    let form: String
    let status: String
    let scheduleJSON: String?
    let startDate: Date?
    let endDate: Date?
    let instructions: String?
    let colorHex: String?
    let fdaIngredients: [String]
    let createdAt: Date
}

nonisolated struct MarkDoseTakenPayload: Codable, Sendable, Equatable {
    let doseId: UUID
    let medicationId: UUID
    let takenAt: Date
    let markedByAppleUserID: String?
    let notes: String?
}

nonisolated struct MarkDoseSkippedPayload: Codable, Sendable, Equatable {
    let doseId: UUID
    let medicationId: UUID
    let skippedAt: Date
    let markedByAppleUserID: String?
    let notes: String?
}

// MARK: - Appointments

nonisolated struct CreateAppointmentPayload: Codable, Sendable, Equatable {
    let appointmentId: UUID
    let title: String
    let provider: String?
    let location: String?
    let startsAt: Date
    let durationMinutes: Int
    let prepNotes: String?
    let reminderOffsetsMinutes: [Int]
    let createdByAppleUserID: String
    let createdByDisplayName: String
    let createdAt: Date
}

// MARK: - Members

nonisolated struct CreateMemberPayload: Codable, Sendable, Equatable {
    let memberId: UUID
    let appleUserID: String
    let displayName: String
    let role: String
    let status: String
    let joinedAt: Date
    let invitedAt: Date?
    let invitedByAppleUserID: String?
    let inviteShareURLString: String?
}

// MARK: - Emergency contacts

nonisolated struct CreateEmergencyContactPayload: Codable, Sendable, Equatable {
    let contactId: UUID
    let name: String
    let relationship: String?
    let phoneE164: String
    let isPrimary: Bool
    let isMedical: Bool
    let sortOrder: Int
    let createdAt: Date
}

// MARK: - Care minutes

nonisolated struct CreateCareMinuteEntryPayload: Codable, Sendable, Equatable {
    let entryId: UUID
    let caregiverAppleUserID: String
    let caregiverDisplayName: String
    let serviceCode: String
    let serviceDescription: String
    let startedAt: Date
    let endedAt: Date
    let notes: String?
    let milesDriven: Double?
    let fiscalIntermediary: String?
}

// MARK: - SOS

nonisolated struct CreateSOSEventPayload: Codable, Sendable, Equatable {
    let eventId: UUID
    let triggeredByAppleUserID: String
    let triggeredByDisplayName: String
    let triggeredAt: Date
    let latitude: Double?
    let longitude: Double?
    let locationAccuracyMeters: Double?
}

// MARK: - Shift digests

nonisolated struct CreateShiftDigestPayload: Codable, Sendable, Equatable {
    let digestId: UUID
    let shiftStartAt: Date
    let shiftEndAt: Date
    let narratorAppleUserID: String
    let narratorDisplayName: String
    let transcript: String?
    let summary: String?
    let audioDurationSeconds: Double
    let extractedEntitiesJSON: String?
    let structuredArtifactsJSON: String?
    let relatedShiftID: UUID?
    let createdAt: Date
}

// MARK: - Sync wire format

/// `POST /v1/sync/batch` response envelope.
nonisolated struct SyncBatchResponse: Decodable, Sendable {
    let acks: [Ack]

    nonisolated struct Ack: Decodable, Sendable, Equatable {
        let clientOpId: UUID
        let status: Status

        nonisolated enum Status: String, Decodable, Sendable {
            case queued
            case duplicate
        }
    }
}
