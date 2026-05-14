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

        let existing = fetchExistingIDs(SOSEvent.self, circleId: circleId, modelContext: modelContext) {
            $0.circle?.id
        }

        let currentUserId = currentBackendUserId()
        var insertedRows: [(event: SOSEvent, dto: SOSEventDTO)] = []
        for dto in response.events {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let event = BackendHydratorMappers.makeSOSEvent(from: dto)
            event.circle = circle
            let displayName = lookupMemberDisplayName(
                backendUserId: dto.triggeredBy,
                circleId: circleId,
                modelContext: modelContext
            )
            if let displayName {
                event.triggeredByDisplayName = displayName
            }
            modelContext.insert(event)
            insertedRows.append((event: event, dto: dto))
        }

        guard !insertedRows.isEmpty else { return }
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: inserted \(insertedRows.count, privacy: .public) sos for circle \(circleId.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after sos merge: \(String(describing: error), privacy: .public)"
            )
            return
        }

        for (event, dto) in insertedRows {
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
            logRefetchFailure(domain: "dose", error: error)
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
        guard !doseEventExists(id: rowId, modelContext: modelContext) else { return }

        let dose = BackendHydratorMappers.makeDoseEvent(from: response.asDoseDTO)
        dose.medication = medication
        modelContext.insert(dose)
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: inserted dose \(rowId.uuidString, privacy: .public) for medication \(medication.id.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after dose insert: \(String(describing: error), privacy: .public)"
            )
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
        let existing = fetchExistingIDs(CareMinuteEntry.self, circleId: circleId, modelContext: modelContext) {
            $0.circle?.id
        }
        var inserted = 0
        for dto in response.entries {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeCareMinuteEntry(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "care-minutes", circleId: circleId, modelContext: modelContext)
    }

    // MARK: - Helpers

    private func fetchMedication(id: UUID, modelContext: ModelContext) -> Medication? {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func doseEventExists(id: UUID, modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
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
        do {
            try await UNUserNotificationCenter.current().add(request)
            AppLogger.backend.info(
                "Realtime: posted SOS notification for event \(event.id.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: SOS notification failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
