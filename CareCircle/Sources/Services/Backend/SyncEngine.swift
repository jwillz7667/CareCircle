import Foundation
import OSLog
import SwiftData

// MARK: - SyncEngine

/// Drains the durable `PendingOperation` queue to the Railway backend.
///
/// The engine is the single owner of the write-through path: features
/// keep using SwiftData/CloudKit as today, then call
/// `enqueueActivityCreate(_:)` (or future siblings) which appends a
/// `PendingOperation` row and triggers a drain. Idempotency is provided
/// by the per-op `clientOpId` — replays after a crash or a 5xx never
/// duplicate server-side rows.
///
/// Concurrent drain attempts are coalesced via `inFlightDrain`. On
/// success, ack'd rows are deleted; on auth failure the engine flips to
/// `.offline` and waits for the next trigger (foreground, sign-in, or
/// manual retry).
@Observable
@MainActor
final class SyncEngine {
    enum Status: Equatable, Sendable {
        case idle
        case draining
        case offline
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var pendingCount = 0

    private let apiClient: APIClient
    private let modelContainer: ModelContainer
    private let encoder: JSONEncoder

    private var inFlightDrain: Task<Void, Never>?

    /// `POST /v1/sync/batch` accepts at most 100 ops per call; chunk
    /// below that to keep payloads under the API's 1 MB body cap with
    /// room for future per-op growth.
    private static let batchChunkSize = 50

    init(
        apiClient: APIClient,
        modelContainer: ModelContainer
    ) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncEngine.isoFormatter.string(from: date))
        }
        self.encoder = encoder
    }

    /// Refreshes the cached `pendingCount` from the durable queue. Cheap
    /// — call from view models that surface the count.
    func refreshPendingCount() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<PendingOperation>()
        do {
            pendingCount = try context.fetchCount(descriptor)
        } catch {
            AppLogger.sync.error(
                "Failed to fetch pending op count: \(String(describing: error), privacy: .public)"
            )
            pendingCount = 0
        }
    }

    /// Enqueues a backend mirror for an activity that was just written
    /// to SwiftData. Returns immediately — actual transport happens in
    /// the next drain pass.
    func enqueueActivityCreate(_ activity: Activity) {
        enqueue(
            operationType: SyncOperationType.createActivity,
            circleId: activity.circle?.id,
            payload: CreateActivityPayload(
                activityId: activity.id,
                type: activity.type.rawValue,
                body: activity.body,
                createdAt: activity.createdAt,
                authorAppleUserID: activity.authorAppleUserID,
                authorDisplayName: activity.authorDisplayName,
                audioDurationSeconds: activity.audioDurationSeconds,
                extractedEntitiesJSON: activity.extractedEntitiesJSON
            )
        )
    }

    func enqueueMedicationCreate(_ medication: Medication) {
        enqueue(
            operationType: SyncOperationType.createMedication,
            circleId: medication.circle?.id,
            payload: CreateMedicationPayload(
                medicationId: medication.id,
                name: medication.name,
                dosage: medication.dosage,
                form: medication.form.rawValue,
                status: medication.status.rawValue,
                scheduleJSON: medication.scheduleJSON,
                startDate: medication.startDate,
                endDate: medication.endDate,
                instructions: medication.instructions,
                colorHex: medication.colorHex,
                fdaIngredients: medication.fdaIngredients,
                createdAt: medication.createdAt
            )
        )
    }

    func enqueueDoseTaken(_ dose: DoseEvent) {
        guard let medication = dose.medication else { return }
        enqueue(
            operationType: SyncOperationType.markDoseTaken,
            circleId: medication.circle?.id,
            payload: MarkDoseTakenPayload(
                doseId: dose.id,
                medicationId: medication.id,
                takenAt: dose.takenAt ?? .now,
                markedByAppleUserID: dose.markedByAppleUserID,
                notes: dose.notes
            )
        )
    }

    func enqueueDoseSkipped(_ dose: DoseEvent) {
        guard let medication = dose.medication else { return }
        enqueue(
            operationType: SyncOperationType.markDoseSkipped,
            circleId: medication.circle?.id,
            payload: MarkDoseSkippedPayload(
                doseId: dose.id,
                medicationId: medication.id,
                skippedAt: dose.updatedAt,
                markedByAppleUserID: dose.markedByAppleUserID,
                notes: dose.notes
            )
        )
    }

    func enqueueAppointmentCreate(_ appointment: Appointment) {
        enqueue(
            operationType: SyncOperationType.createAppointment,
            circleId: appointment.circle?.id,
            payload: CreateAppointmentPayload(
                appointmentId: appointment.id,
                title: appointment.title,
                provider: appointment.provider,
                location: appointment.location,
                startsAt: appointment.startsAt,
                durationMinutes: appointment.durationMinutes,
                prepNotes: appointment.prepNotes,
                reminderOffsetsMinutes: appointment.reminderOffsetsMinutes,
                createdByAppleUserID: appointment.createdByAppleUserID,
                createdByDisplayName: appointment.createdByDisplayName,
                createdAt: appointment.createdAt
            )
        )
    }

    func enqueueMemberCreate(_ member: Member) {
        enqueue(
            operationType: SyncOperationType.createMember,
            circleId: member.circle?.id,
            payload: CreateMemberPayload(
                memberId: member.id,
                appleUserID: member.appleUserID,
                displayName: member.displayName,
                role: member.role.rawValue,
                status: member.status.rawValue,
                joinedAt: member.joinedAt,
                invitedAt: member.invitedAt,
                invitedByAppleUserID: member.invitedByAppleUserID,
                inviteShareURLString: member.inviteShareURLString
            )
        )
    }

    func enqueueEmergencyContactCreate(_ contact: EmergencyContact) {
        enqueue(
            operationType: SyncOperationType.createEmergencyContact,
            circleId: contact.circle?.id,
            payload: CreateEmergencyContactPayload(
                contactId: contact.id,
                name: contact.name,
                relationship: contact.relationship,
                phoneE164: contact.phoneE164,
                isPrimary: contact.isPrimary,
                isMedical: contact.isMedical,
                sortOrder: contact.sortOrder,
                createdAt: contact.createdAt
            )
        )
    }

    func enqueueCareMinuteCreate(_ entry: CareMinuteEntry) {
        enqueue(
            operationType: SyncOperationType.createCareMinuteEntry,
            circleId: entry.circle?.id,
            payload: CreateCareMinuteEntryPayload(
                entryId: entry.id,
                caregiverAppleUserID: entry.caregiverAppleUserID,
                caregiverDisplayName: entry.caregiverDisplayName,
                serviceCode: entry.serviceCode.rawValue,
                serviceDescription: entry.serviceDescription,
                startedAt: entry.startedAt,
                endedAt: entry.endedAt,
                notes: entry.notes,
                milesDriven: entry.milesDriven,
                fiscalIntermediary: entry.fiscalIntermediary
            )
        )
    }

    func enqueueSOSEventCreate(_ event: SOSEvent) {
        enqueue(
            operationType: SyncOperationType.createSOSEvent,
            circleId: event.circle?.id,
            payload: CreateSOSEventPayload(
                eventId: event.id,
                triggeredByAppleUserID: event.triggeredByAppleUserID,
                triggeredByDisplayName: event.triggeredByDisplayName,
                triggeredAt: event.triggeredAt,
                latitude: event.latitude,
                longitude: event.longitude,
                locationAccuracyMeters: event.locationAccuracyMeters
            )
        )
    }

    private func enqueue(
        operationType: String,
        circleId: UUID?,
        payload: some Encodable & Sendable
    ) {
        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            AppLogger.sync.error(
                "Failed to encode \(operationType, privacy: .public) payload: \(String(describing: error), privacy: .public)"
            )
            return
        }

        let context = modelContainer.mainContext
        let operation = PendingOperation(
            operationType: operationType,
            circleId: circleId,
            payloadJSON: payloadData
        )
        context.insert(operation)
        do {
            try context.save()
        } catch {
            AppLogger.sync.error(
                "Failed to persist pending op: \(String(describing: error), privacy: .public)"
            )
            return
        }

        refreshPendingCount()
        triggerDrain()
    }

    /// Public entrypoint: schedules a drain pass unless one is already
    /// running. Safe to call from app-foreground, sign-in completion,
    /// or a manual retry button.
    func triggerDrain() {
        guard inFlightDrain == nil else { return }
        inFlightDrain = Task { [weak self] in
            await self?.drainOnce()
            await MainActor.run {
                self?.inFlightDrain = nil
            }
        }
    }

    private enum ChunkOutcome {
        case sent
        case deferred(String)
        case failed(String)
    }

    private func drainOnce() async {
        guard await apiClient.tokenStore.currentTokens() != nil else {
            status = .offline
            return
        }

        let context = modelContainer.mainContext
        let pending = fetchPendingOperations(context: context)
        guard let pending else { return }

        guard !pending.isEmpty else {
            status = .idle
            lastError = nil
            pendingCount = 0
            return
        }

        status = .draining
        var sentAny = false

        for chunk in pending.chunked(into: Self.batchChunkSize) {
            switch await sendChunk(chunk, context: context) {
            case .sent:
                sentAny = true
            case let .deferred(message):
                status = .offline
                lastError = message
                return
            case let .failed(message):
                status = .error(message)
                lastError = message
                return
            }
        }

        if sentAny {
            lastSyncAt = .now
        }
        lastError = nil
        status = .idle
        refreshPendingCount()
    }

    private func fetchPendingOperations(context: ModelContext) -> [PendingOperation]? {
        let descriptor = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLogger.sync.error(
                "Failed to fetch pending ops: \(String(describing: error), privacy: .public)"
            )
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
            return nil
        }
    }

    private func sendChunk(
        _ chunk: [PendingOperation],
        context: ModelContext
    ) async
        -> ChunkOutcome
    {
        let bodyData: Data
        do {
            bodyData = try buildBatchBody(operations: chunk)
        } catch {
            AppLogger.sync.error(
                "Failed to assemble sync batch body: \(String(describing: error), privacy: .public)"
            )
            return .failed("Failed to assemble sync payload.")
        }

        do {
            let response: SyncBatchResponse = try await apiClient.sendRawJSON(
                method: .post,
                path: "/v1/sync/batch",
                body: bodyData
            )
            let acked = Set(response.acks.map(\.clientOpId))
            for op in chunk where acked.contains(op.clientOpId) {
                context.delete(op)
            }
            try context.save()
            AppLogger.sync.info(
                "Sync batch acked \(response.acks.count, privacy: .public) ops."
            )
            return .sent
        } catch let apiError as APIError {
            return handleAPIFailure(apiError, chunk: chunk, context: context)
        } catch {
            AppLogger.sync.error(
                "Save after sync ack failed: \(String(describing: error), privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    private func handleAPIFailure(
        _ error: APIError,
        chunk: [PendingOperation],
        context: ModelContext
    )
        -> ChunkOutcome
    {
        let message = error.errorDescription ?? "Sync failed."
        if error.isAuthFailure {
            AppLogger.sync.notice("Sync deferred: \(message, privacy: .public)")
            return .deferred(message)
        }
        for op in chunk {
            op.attemptCount += 1
            op.lastAttemptAt = .now
            op.lastErrorMessage = message
        }
        try? context.save()
        AppLogger.sync.error("Sync batch failed: \(message, privacy: .public)")
        return .failed(message)
    }

    /// Builds the `POST /v1/sync/batch` body from durable queue rows.
    /// Each row's stored `payloadJSON` is re-parsed and embedded as the
    /// op's `payload` field so the wire format stays a homogeneous
    /// JSON document regardless of the underlying payload type.
    private func buildBatchBody(
        operations: [PendingOperation]
    ) throws
        -> Data
    {
        var wireOps: [[String: Any]] = []
        wireOps.reserveCapacity(operations.count)
        for op in operations {
            let parsedPayload: Any
            do {
                parsedPayload = try JSONSerialization.jsonObject(with: op.payloadJSON)
            } catch {
                parsedPayload = [String: Any]()
                AppLogger.sync.error(
                    "Discarding malformed payload for op \(op.clientOpId.uuidString, privacy: .public)"
                )
            }
            var dict: [String: Any] = [
                "clientOpId": op.clientOpId.uuidString.lowercased(),
                "operationType": op.operationType,
                "payload": parsedPayload,
            ]
            if let circleId = op.circleId {
                dict["circleId"] = circleId.uuidString.lowercased()
            }
            wireOps.append(dict)
        }
        let envelope: [String: Any] = ["operations": wireOps]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
