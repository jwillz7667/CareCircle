import Foundation

// MARK: - BackendHydratorMappers

//
// Pure DTO → SwiftData model converters used by `BackendHydrator`.
// Lives in its own file so `BackendHydrator.swift` stays the orchestrator
// and the mapping rules sit beside the wire shapes they originate from.
//
// Every mapper is a static method so the converters carry no state and
// are trivially testable in isolation.

@MainActor
enum BackendHydratorMappers {
    static func makeActivity(from dto: ActivityDTO) -> Activity {
        // The backend's `entities` is a flat `[String]`; the iOS model's
        // `extractedEntitiesJSON` decodes into the structured
        // `ExtractedEntities` shape, so the two are incompatible until
        // Phase 17 unifies the wire format. Skip the field for now —
        // existing local activities re-extract on demand via
        // `ActivityExtractionService`.
        Activity(
            id: parseUUID(dto.id) ?? UUID(),
            authorAppleUserID: dto.authorUserId,
            authorDisplayName: "",
            type: ActivityType(rawValue: dto.type) ?? .system,
            body: dto.content ?? dto.headline ?? "",
            createdAt: dto.occurredAt
        )
    }

    static func makeMedication(from dto: MedicationDTO) -> Medication {
        let schedule: MedicationSchedule = {
            guard let envelope = dto.schedule, !envelope.rawJSON.isEmpty else {
                return MedicationSchedule()
            }
            return MedicationSchedule.decode(from: envelope.rawJSON) ?? MedicationSchedule()
        }()
        return Medication(
            id: parseUUID(dto.id) ?? UUID(),
            name: dto.name,
            dosage: dto.dosage,
            form: MedicationForm(rawValue: dto.form ?? "") ?? .other,
            status: MedicationStatus(rawValue: dto.status) ?? .active,
            schedule: schedule,
            instructions: nil,
            colorHex: dto.color,
            fdaIngredients: [],
            startDate: parseShortDate(dto.startDate),
            endDate: parseShortDate(dto.endDate)
        )
    }

    static func makeAppointment(from dto: AppointmentDTO) -> Appointment {
        Appointment(
            id: parseUUID(dto.id) ?? UUID(),
            title: dto.title,
            provider: dto.provider,
            location: dto.location,
            startsAt: dto.startsAt,
            durationMinutes: dto.durationMinutes,
            prepNotes: dto.prepNotes,
            transportResponsibleAppleUserID: dto.transportResponsible,
            reminderOffsetsMinutes: dto.reminderMinutesBefore,
            createdByAppleUserID: "",
            createdByDisplayName: ""
        )
    }

    static func makeEmergencyContact(from dto: EmergencyContactDTO) -> EmergencyContact {
        EmergencyContact(
            id: parseUUID(dto.id) ?? UUID(),
            name: dto.name,
            relationship: dto.relationship,
            phoneE164: dto.phone,
            isPrimary: dto.isPrimary,
            isMedical: dto.isMedical,
            sortOrder: dto.sortOrder
        )
    }

    static func makeMember(from dto: MemberDTO) -> Member {
        // The Apple-user-ID linkage stays with the CKShare acceptance path —
        // the backend's `userId` is a UUID, not an Apple ID. Use the backend
        // UUID as the Apple-user-ID placeholder until Phase 17 reconciles.
        Member(
            id: parseUUID(dto.id) ?? UUID(),
            appleUserID: dto.userId,
            displayName: dto.displayName,
            role: MemberRole(rawValue: dto.role) ?? .viewOnly,
            status: MemberStatus(rawValue: dto.status) ?? .active,
            joinedAt: dto.joinedAt ?? dto.invitedAt,
            invitedAt: dto.invitedAt
        )
    }

    static func makeCareMinuteEntry(from dto: CareMinuteEntryDTO) -> CareMinuteEntry {
        CareMinuteEntry(
            id: parseUUID(dto.id) ?? UUID(),
            caregiverAppleUserID: dto.caregiverUserId,
            caregiverDisplayName: "",
            serviceCode: HCBSServiceCode(rawValue: dto.serviceCode) ?? .other,
            serviceDescription: dto.serviceDescription,
            startedAt: dto.startedAt,
            endedAt: dto.endedAt,
            notes: dto.notes,
            fiscalIntermediary: dto.fiscalIntermediary
        )
    }

    static func makeSOSEvent(from dto: SOSEventDTO) -> SOSEvent {
        let event = SOSEvent(
            id: parseUUID(dto.id) ?? UUID(),
            triggeredByAppleUserID: dto.triggeredBy,
            triggeredByDisplayName: "",
            triggeredAt: dto.triggeredAt,
            latitude: dto.locationLat,
            longitude: dto.locationLng
        )
        event.canceledAt = dto.canceledAt
        event.canceledByAppleUserID = dto.canceledBy
        return event
    }

    /// Documents hydrate as **placeholders**: backend metadata is
    /// authoritative but the encrypted blob still lives in MinIO. The
    /// caller's `BackendDocumentService` would have to GET the
    /// presigned download URL + decrypt with the per-circle DEK to
    /// produce viewable plaintext, neither of which is wired in v1.
    /// The empty `ciphertext/nonce/tag` triple plus the populated
    /// `backendObjectKey` is what `DocumentRowView` reads to render the
    /// "Backend only" badge.
    static func makeDocumentPlaceholder(from dto: DocumentDTO) -> Document {
        Document(
            id: parseUUID(dto.id) ?? UUID(),
            title: dto.title,
            type: DocumentType(rawValue: dto.documentType) ?? .other,
            mimeType: dto.mimeType,
            sizeBytes: dto.sizeBytes,
            ciphertext: Data(),
            nonce: Data(),
            tag: Data(),
            issuedAt: parseShortDate(dto.issuedAt),
            expiresAt: parseShortDate(dto.expiresAt),
            visibilityRoles: DocumentVisibility.defaultRoles,
            uploadedByAppleUserID: dto.uploadedBy,
            uploadedByDisplayName: "",
            createdAt: dto.createdAt,
            backendObjectKey: dto.objectKey
        )
    }

    // MARK: - Parsing helpers

    static func parseUUID(_ raw: String) -> UUID? {
        UUID(uuidString: raw)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseShortDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return shortDateFormatter.date(from: raw)
    }
}
