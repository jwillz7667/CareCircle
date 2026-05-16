import Foundation

// MARK: - BackendReadDTOs

//
// Decoded payloads for the inbound hydration reads (Phase 16). Each
// response struct mirrors a single GET handler in the Railway backend.
// Field names match the camelCase keys the routes emit verbatim — the
// `APIClient.decoder` does not apply a key-conversion strategy, so any
// mismatch here surfaces as a decoding error at the boundary.
//
// These types are intentionally read-only: hydration converts them into
// the existing `@Model` types in `BackendHydrator`. Keeping the DTOs
// detached from SwiftData avoids the actor-isolation gymnastics of
// instantiating models in a Sendable context.

// MARK: - Circles

nonisolated struct CircleSummariesResponse: Decodable, Sendable, Equatable {
    let circles: [CircleSummaryDTO]
}

nonisolated struct CircleSummaryDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let ownerUserId: String
    let subscriptionTier: String
    let subscriptionStatus: String
    let createdAt: Date
    let memberCount: Int
}

// MARK: - Activities

nonisolated struct ActivitiesResponse: Decodable, Sendable, Equatable {
    let activities: [ActivityDTO]
    let nextCursor: String?
}

nonisolated struct ActivityDTO: Decodable, Sendable, Equatable {
    let id: String
    let authorUserId: String
    let type: String
    let headline: String?
    let content: String?
    let voiceObjectKey: String?
    let photoObjectKeys: [String]
    let entities: [String]
    let relatedMedId: String?
    let relatedAppointmentId: String?
    let relatedShiftId: String?
    let occurredAt: Date
    let version: Int
}

// MARK: - Medications

nonisolated struct MedicationsResponse: Decodable, Sendable, Equatable {
    let medications: [MedicationDTO]
}

nonisolated struct MedicationDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let genericName: String?
    let dosage: String
    let form: String?
    let rxcui: String?
    let color: String?
    let status: String
    /// Raw JSON object from `medications.schedule`. Kept as a stringified
    /// payload so we can hand the bytes straight to `MedicationSchedule`'s
    /// decoder without re-modeling the union here.
    let schedule: ScheduleEnvelope?
    /// `YYYY-MM-DD` strings; the backend slices off the time component.
    let startDate: String?
    let endDate: String?
}

/// Wraps an arbitrary JSON object so we can decode the medication
/// `schedule` column without coupling this file to the
/// `MedicationSchedule` shape. The raw bytes are re-encoded on read.
nonisolated struct ScheduleEnvelope: Decodable, Sendable, Equatable {
    let rawJSON: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            rawJSON = ""
            return
        }
        let value = try container.decode(JSONValue.self)
        let data = try JSONEncoder().encode(value)
        rawJSON = String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Appointments

nonisolated struct AppointmentsResponse: Decodable, Sendable, Equatable {
    let appointments: [AppointmentDTO]
}

nonisolated struct AppointmentDTO: Decodable, Sendable, Equatable {
    let id: String
    let title: String
    let provider: String?
    let location: String?
    let startsAt: Date
    let durationMinutes: Int
    let transportResponsible: String?
    let prepNotes: String?
    let reminderMinutesBefore: [Int]
}

// MARK: - Emergency contacts

nonisolated struct EmergencyContactsResponse: Decodable, Sendable, Equatable {
    let contacts: [EmergencyContactDTO]
}

nonisolated struct EmergencyContactDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let relationship: String?
    let phone: String
    let isPrimary: Bool
    let isMedical: Bool
    let sortOrder: Int
}

// MARK: - Members

nonisolated struct MembersResponse: Decodable, Sendable, Equatable {
    let members: [MemberDTO]
}

nonisolated struct MemberDTO: Decodable, Sendable, Equatable {
    let id: String
    let userId: String
    let role: String
    let status: String
    let displayName: String
    let joinedAt: Date?
    let invitedAt: Date
    let photoObjectKey: String?
}

// MARK: - Care minutes

nonisolated struct CareMinutesResponse: Decodable, Sendable, Equatable {
    let entries: [CareMinuteEntryDTO]
}

nonisolated struct CareMinuteEntryDTO: Decodable, Sendable, Equatable {
    let id: String
    let caregiverUserId: String
    let serviceCode: String
    let serviceDescription: String
    let startedAt: Date
    let endedAt: Date
    let durationMinutes: Int
    let notes: String?
    let fiscalIntermediary: String?
    let exportedAt: Date?
}

// MARK: - SOS

nonisolated struct SOSEventsResponse: Decodable, Sendable, Equatable {
    let events: [SOSEventDTO]
}

nonisolated struct SOSEventDTO: Decodable, Sendable, Equatable {
    let id: String
    let triggeredBy: String
    let triggeredAt: Date
    let canceledAt: Date?
    let canceledBy: String?
    let locationLat: Double?
    let locationLng: Double?
}

// MARK: - Documents

nonisolated struct DocumentsResponse: Decodable, Sendable, Equatable {
    let documents: [DocumentDTO]
}

nonisolated struct DocumentDTO: Decodable, Sendable, Equatable {
    let id: String
    let title: String
    let documentType: String
    let objectKey: String
    let mimeType: String
    let sizeBytes: Int
    /// `YYYY-MM-DD` UTC strings; backend slices off the time component.
    let issuedAt: String?
    let expiresAt: String?
    let uploadedBy: String
    let createdAt: Date
}

/// Response from `POST /v1/circles/:id/documents/upload-url`.
nonisolated struct DocumentUploadURLResponse: Decodable, Sendable, Equatable {
    let bucket: String
    let objectKey: String
    let url: String
    let expiresInSeconds: Int
}

/// Response from `POST /v1/circles/:id/documents`.
nonisolated struct DocumentCreateResponse: Decodable, Sendable, Equatable {
    let id: String
}

/// Response from `GET /v1/documents/:id/download-url`.
nonisolated struct DocumentDownloadURLResponse: Decodable, Sendable, Equatable {
    let url: String
    let objectKey: String
    let encryptionNonce: String
    let encryptionTag: String
}

// MARK: - Medication dose events

nonisolated struct MedicationDosesResponse: Decodable, Sendable, Equatable {
    let doses: [DoseDTO]
}

nonisolated struct DoseDTO: Decodable, Sendable, Equatable {
    let id: String
    let scheduledAt: Date
    let takenAt: Date?
    let markedBy: String?
    let status: String
    let notes: String?
}

/// Response from `GET /v1/doses/:id`. Same per-dose shape as `DoseDTO`
/// plus the parent IDs so a realtime applicator can attach the row to
/// the right local `Medication` without an additional round trip.
nonisolated struct DoseByIdResponse: Decodable, Sendable, Equatable {
    let id: String
    let medicationId: String
    let circleId: String
    let scheduledAt: Date
    let takenAt: Date?
    let markedBy: String?
    let status: String
    let notes: String?

    /// Lossy down-conversion to a `DoseDTO` for re-use of the existing
    /// `BackendHydratorMappers.makeDoseEvent` mapper.
    var asDoseDTO: DoseDTO {
        DoseDTO(
            id: id,
            scheduledAt: scheduledAt,
            takenAt: takenAt,
            markedBy: markedBy,
            status: status,
            notes: notes
        )
    }
}

// MARK: - Shift digests

nonisolated struct ShiftDigestsResponse: Decodable, Sendable, Equatable {
    let digests: [ShiftDigestDTO]
    let nextCursor: String?
}

nonisolated struct ShiftDigestDTO: Decodable, Sendable, Equatable {
    let id: String
    let circleId: String
    let narratorUserId: String
    let shiftStartAt: Date
    let shiftEndAt: Date
    let transcript: String?
    let summary: String?
    let entities: ExtractedEntities?
    let artifacts: ShiftDigestArtifactsSnapshot?
    let voiceObjectKey: String?
    let audioDurationSeconds: Double
    let relatedShiftId: String?
    let createdAt: Date
    let version: Int
}

// MARK: - Vitals

nonisolated struct VitalsResponse: Decodable, Sendable, Equatable {
    let vitals: [VitalDTO]
    let nextCursor: String?
}

nonisolated struct VitalDTO: Decodable, Sendable, Equatable {
    let id: String
    let circleId: String
    let recordedByUserId: String
    let kind: String
    let recordedAt: Date
    let valueNumeric: Double?
    let valueText: String?
    let unit: String
    let source: String
    let healthkitUUID: String?
    let notes: String?
    let createdAt: Date
    let version: Int
}

// MARK: - JSONValue

/// Minimal JSON value used to round-trip the medication `schedule`
/// blob. Decoding any JSON shape and re-encoding it gives us the raw
/// payload as a `String` we can hand to `MedicationSchedule.decode`.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
