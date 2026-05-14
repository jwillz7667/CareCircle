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

    static func makeDoseEvent(from dto: DoseDTO) -> DoseEvent {
        DoseEvent(
            id: parseUUID(dto.id) ?? UUID(),
            scheduledAt: dto.scheduledAt,
            status: DoseStatus(rawValue: dto.status) ?? .scheduled,
            takenAt: dto.takenAt,
            markedByAppleUserID: dto.markedBy,
            markedByDisplayName: nil,
            notes: dto.notes
        )
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

    // MARK: - Update mappers (Phase 23)

    // In-place updates that only touch fields the backend is
    // authoritative for. CloudKit-only state — photo / audio blobs on
    // `Activity`, the encrypted blob triple on `Document`,
    // `milesDriven` on `CareMinuteEntry`, the dose-to-medication
    // relationship, etc. — is left alone so realtime fan-out does not
    // stomp on locally-set values.

    static func updateActivity(_ activity: Activity, from dto: ActivityDTO) {
        activity.authorAppleUserID = dto.authorUserId
        activity.typeRaw = (ActivityType(rawValue: dto.type) ?? .system).rawValue
        activity.body = dto.content ?? dto.headline ?? ""
        activity.createdAt = dto.occurredAt
    }

    static func updateMedication(_ medication: Medication, from dto: MedicationDTO) {
        medication.name = dto.name
        medication.dosage = dto.dosage
        medication.formRaw = (MedicationForm(rawValue: dto.form ?? "") ?? .other).rawValue
        medication.statusRaw = (MedicationStatus(rawValue: dto.status) ?? .active).rawValue
        medication.colorHex = dto.color
        if let envelope = dto.schedule, !envelope.rawJSON.isEmpty {
            medication.scheduleJSON = envelope.rawJSON
        }
        medication.startDate = parseShortDate(dto.startDate)
        medication.endDate = parseShortDate(dto.endDate)
        medication.updatedAt = .now
    }

    static func updateAppointment(_ appointment: Appointment, from dto: AppointmentDTO) {
        appointment.title = dto.title
        appointment.provider = dto.provider
        appointment.location = dto.location
        appointment.startsAt = dto.startsAt
        appointment.durationMinutes = dto.durationMinutes
        appointment.prepNotes = dto.prepNotes
        appointment.transportResponsibleAppleUserID = dto.transportResponsible
        appointment.reminderOffsetsMinutes = dto.reminderMinutesBefore
        appointment.updatedAt = .now
    }

    static func updateMember(_ member: Member, from dto: MemberDTO) {
        member.appleUserID = dto.userId
        member.displayName = dto.displayName
        member.roleRaw = (MemberRole(rawValue: dto.role) ?? .viewOnly).rawValue
        member.statusRaw = (MemberStatus(rawValue: dto.status) ?? .active).rawValue
        member.joinedAt = dto.joinedAt ?? dto.invitedAt
        member.invitedAt = dto.invitedAt
    }

    static func updateEmergencyContact(
        _ contact: EmergencyContact,
        from dto: EmergencyContactDTO
    ) {
        contact.name = dto.name
        contact.relationship = dto.relationship
        contact.phoneE164 = dto.phone
        contact.isPrimary = dto.isPrimary
        contact.isMedical = dto.isMedical
        contact.sortOrder = dto.sortOrder
        contact.updatedAt = .now
    }

    static func updateDocument(_ document: Document, from dto: DocumentDTO) {
        document.title = dto.title
        document.typeRaw = (DocumentType(rawValue: dto.documentType) ?? .other).rawValue
        document.mimeType = dto.mimeType
        document.sizeBytes = dto.sizeBytes
        document.issuedAt = parseShortDate(dto.issuedAt)
        document.expiresAt = parseShortDate(dto.expiresAt)
        document.uploadedByAppleUserID = dto.uploadedBy
        document.backendObjectKey = dto.objectKey
        document.updatedAt = .now
    }

    /// Updates an existing `SOSEvent`. `triggeredByDisplayName` is only
    /// overwritten when the caller supplies a non-empty value; passing
    /// `nil` keeps whatever name was resolved on the original insert.
    static func updateSOSEvent(
        _ event: SOSEvent,
        from dto: SOSEventDTO,
        displayName: String?
    ) {
        event.triggeredByAppleUserID = dto.triggeredBy
        event.triggeredAt = dto.triggeredAt
        event.latitude = dto.locationLat
        event.longitude = dto.locationLng
        event.canceledAt = dto.canceledAt
        event.canceledByAppleUserID = dto.canceledBy
        if let displayName, !displayName.isEmpty {
            event.triggeredByDisplayName = displayName
        }
    }

    static func updateCareMinuteEntry(
        _ entry: CareMinuteEntry,
        from dto: CareMinuteEntryDTO
    ) {
        entry.caregiverAppleUserID = dto.caregiverUserId
        entry.serviceCodeRaw = (HCBSServiceCode(rawValue: dto.serviceCode) ?? .other).rawValue
        entry.serviceDescription = dto.serviceDescription
        entry.startedAt = dto.startedAt
        entry.endedAt = dto.endedAt
        entry.notes = dto.notes
        entry.fiscalIntermediary = dto.fiscalIntermediary
        entry.updatedAt = .now
    }

    static func updateDoseEvent(_ dose: DoseEvent, from dto: DoseDTO) {
        dose.scheduledAt = dto.scheduledAt
        dose.takenAt = dto.takenAt
        dose.statusRaw = (DoseStatus(rawValue: dto.status) ?? .scheduled).rawValue
        dose.markedByAppleUserID = dto.markedBy
        dose.notes = dto.notes
        dose.updatedAt = .now
    }

    static func makeShiftDigest(from dto: ShiftDigestDTO) -> ShiftDigest {
        let extractedJSON = dto.entities?.encodedJSON()
        let artifactsJSON = dto.artifacts?.encodedJSON()
        return ShiftDigest(
            id: parseUUID(dto.id) ?? UUID(),
            shiftStartAt: dto.shiftStartAt,
            shiftEndAt: dto.shiftEndAt,
            narratorAppleUserID: dto.narratorUserId,
            narratorDisplayName: "",
            transcript: dto.transcript ?? "",
            summary: dto.summary,
            audioData: nil,
            audioDurationSeconds: dto.audioDurationSeconds,
            extractedEntitiesJSON: extractedJSON,
            structuredArtifactsJSON: artifactsJSON,
            relatedShiftID: parseUUID(dto.relatedShiftId ?? ""),
            createdAt: dto.createdAt
        )
    }

    static func updateShiftDigest(_ digest: ShiftDigest, from dto: ShiftDigestDTO) {
        digest.shiftStartAt = dto.shiftStartAt
        digest.shiftEndAt = dto.shiftEndAt
        digest.narratorAppleUserID = dto.narratorUserId
        digest.transcript = dto.transcript ?? ""
        digest.summary = dto.summary
        digest.audioDurationSeconds = dto.audioDurationSeconds
        if let entities = dto.entities {
            digest.extractedEntitiesJSON = entities.encodedJSON()
        }
        if let artifacts = dto.artifacts {
            digest.structuredArtifactsJSON = artifacts.encodedJSON()
        }
        digest.relatedShiftID = parseUUID(dto.relatedShiftId ?? "")
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
