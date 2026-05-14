import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - Phase 22 applicators

/// Realtime applicators added in Phase 22: SOS events (with local
/// notification fan-out), dose events (per-row fetch via new
/// `GET /v1/doses/:id`), and care-minute entries.
///
/// Kept separate from `BackendRealtimeClient` to keep that file under
/// the swiftlint length thresholds. All three follow the same
/// idempotent-insert-by-UUID property as Phase 20 / 21, with two extra
/// concerns: SOS lookups the member display name for the notification
/// body, and dose events attach to a parent `Medication` looked up by
/// the per-row response's `medicationId`.
extension BackendRealtimeClient {
    func applySosChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: SOSEventsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/sos",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "sos", error: error)
            return
        }
        let merged = mergeSOSEvents(
            dtos: response.events,
            circle: circle,
            circleId: circleId,
            modelContext: modelContext
        )
        guard !merged.insertedRows.isEmpty || merged.updatedCount > 0 else { return }
        guard saveSOSMerge(
            modelContext: modelContext,
            circleId: circleId,
            insertedCount: merged.insertedRows.count,
            updatedCount: merged.updatedCount
        ) else { return }
        let currentUserId = currentBackendUserId()
        for (event, dto) in merged.insertedRows {
            guard shouldNotifyForIncomingSOS(dto: dto, currentUserId: currentUserId) else { continue }
            await postIncomingSOSNotification(event: event)
        }
    }

    func applyDoseChange(
        rowId: UUID,
        modelContext: ModelContext
    ) async {
        let response: DoseByIdResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/doses/\(rowId.uuidString.lowercased())",
                authenticated: true
            )
        } catch {
            handleDoseFetchError(error: error, rowId: rowId, modelContext: modelContext)
            return
        }
        guard let medicationId = BackendHydratorMappers.parseUUID(response.medicationId),
              let medication = fetchMedication(id: medicationId, modelContext: modelContext) else
        {
            AppLogger.backend.debug(
                "Realtime: dose \(rowId.uuidString, privacy: .public) parent medication not local — skipping."
            )
            return
        }

        if let existing = fetchDoseEvent(id: rowId, modelContext: modelContext) {
            BackendHydratorMappers.updateDoseEvent(existing, from: response.asDoseDTO)
            saveDoseChange(rowId: rowId, action: "updated", modelContext: modelContext)
        } else {
            let dose = BackendHydratorMappers.makeDoseEvent(from: response.asDoseDTO)
            dose.medication = medication
            modelContext.insert(dose)
            saveDoseChange(rowId: rowId, action: "inserted", modelContext: modelContext)
        }
    }

    func applyCareMinuteChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: CareMinutesResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/care-minutes",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "care-minutes", error: error)
            return
        }
        // 500-row response window: cold-start hydration owns soft-delete
        // propagation. Upsert-only here.
        upsertList(
            response.entries,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "care-minutes",
                deleteAbsent: false,
                circleIDOf: { (row: CareMinuteEntry) in row.circle?.id },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeCareMinuteEntry(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateCareMinuteEntry(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
    }

    // MARK: - Helpers

    /// Outcome of merging a `/sos` refetch into SwiftData. The caller
    /// uses `insertedRows` to drive the incoming-SOS notification fan
    /// out (only new events trigger a notification — updates to
    /// existing rows, e.g. cancellation, must not re-alert).
    struct SOSMergeResult {
        let insertedRows: [(event: SOSEvent, dto: SOSEventDTO)]
        let updatedCount: Int
    }

    private func mergeSOSEvents(
        dtos: [SOSEventDTO],
        circle: Circle,
        circleId: UUID,
        modelContext: ModelContext
    )
        -> SOSMergeResult
    {
        let localMap = fetchLocalSOSMap(circleId: circleId, modelContext: modelContext)
        var insertedRows: [(event: SOSEvent, dto: SOSEventDTO)] = []
        var updatedCount = 0
        for dto in dtos {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id) else { continue }
            let displayName = lookupMemberDisplayName(
                backendUserId: dto.triggeredBy,
                circleId: circleId,
                modelContext: modelContext
            )
            if let existing = localMap[dtoID] {
                BackendHydratorMappers.updateSOSEvent(existing, from: dto, displayName: displayName)
                updatedCount += 1
            } else {
                let event = BackendHydratorMappers.makeSOSEvent(from: dto)
                event.circle = circle
                if let displayName {
                    event.triggeredByDisplayName = displayName
                }
                modelContext.insert(event)
                insertedRows.append((event: event, dto: dto))
            }
        }
        return SOSMergeResult(insertedRows: insertedRows, updatedCount: updatedCount)
    }

    /// Returns true when the save committed, so the caller can proceed
    /// to fan out notifications. On save failure the merged inserts are
    /// effectively rolled back (the next change frame re-fetches), so
    /// notifying for them would be wrong.
    private func saveSOSMerge(
        modelContext: ModelContext,
        circleId: UUID,
        insertedCount: Int,
        updatedCount: Int
    )
        -> Bool
    {
        let circleIdString = circleId.uuidString
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: sos for \(circleIdString, privacy: .public): +\(insertedCount, privacy: .public) ~\(updatedCount, privacy: .public)"
            )
            return true
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after sos merge: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func handleDoseFetchError(
        error: Error,
        rowId: UUID,
        modelContext: ModelContext
    ) {
        if case let APIError.http(status, _) = error, status == 404 {
            // The backend dose row is gone (hard-delete or never existed
            // under this user's RLS view). Remove the local row if we
            // had one — otherwise the change is a no-op.
            guard let existing = fetchDoseEvent(id: rowId, modelContext: modelContext) else { return }
            modelContext.delete(existing)
            saveDoseChange(rowId: rowId, action: "deleted", modelContext: modelContext)
        } else {
            logRefetchFailure(domain: "dose", error: error)
        }
    }

    private func saveDoseChange(
        rowId: UUID,
        action: String,
        modelContext: ModelContext
    ) {
        let rowIdString = rowId.uuidString
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: \(action, privacy: .public) dose \(rowIdString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after dose \(action, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func fetchMedication(id: UUID, modelContext: ModelContext) -> Medication? {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchDoseEvent(id: UUID, modelContext: ModelContext) -> DoseEvent? {
        let descriptor = FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchLocalSOSMap(
        circleId: UUID,
        modelContext: ModelContext
    )
        -> [UUID: SOSEvent]
    {
        let all = (try? modelContext.fetch(FetchDescriptor<SOSEvent>())) ?? []
        var map: [UUID: SOSEvent] = [:]
        for event in all where event.circle?.id == circleId {
            map[event.id] = event
        }
        return map
    }

    private func lookupMemberDisplayName(
        backendUserId: String,
        circleId: UUID,
        modelContext: ModelContext
    )
        -> String?
    {
        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.appleUserID == backendUserId }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        guard let member = candidates.first(where: { $0.circle?.id == circleId }) else { return nil }
        let trimmed = member.displayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldNotifyForIncomingSOS(dto: SOSEventDTO, currentUserId: String?) -> Bool {
        if let currentUserId, dto.triggeredBy == currentUserId { return false }
        return dto.canceledAt == nil
    }

    private func postIncomingSOSNotification(event: SOSEvent) async {
        let displayName = event.triggeredByDisplayName.trimmingCharacters(in: .whitespaces)
        let body = displayName.isEmpty
            ? "Someone in your Circle requested help. Tap to view details."
            : "\(displayName) requested help. Tap to view details."
        let content = UNMutableNotificationContent()
        content.title = "SOS triggered"
        content.body = body
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "SOS_EVENT"
        content.userInfo = ["sos_event_id": event.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "sos.event.\(event.id.uuidString)",
            content: content,
            trigger: nil
        )
        let eventIdString = event.id.uuidString
        do {
            try await UNUserNotificationCenter.current().add(request)
            AppLogger.backend.info(
                "Realtime: posted SOS notification for event \(eventIdString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: SOS notification failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
