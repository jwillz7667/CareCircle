import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - Cold-start SOS reconcile (Phase 26)

/// Always-on SOS reconcile that runs as part of every cold-start
/// hydration pass — unlike the other domain hydrators, which skip when
/// their local store is non-empty. The gap this closes: a force-kill +
/// relaunch where iPhone B posted the SOS notification before the kill
/// and the SOS was canceled while B was dead. Neither the realtime
/// snapshot (Phase 24, fires only on *re*connect) nor the empty-store
/// gate of the original hydrator catches that case.
///
/// SOS is backend-fanout only (Phase 22) — there is no CloudKit replica
/// to clobber — so a per-launch refetch is safe. The cost is one extra
/// `/sos` GET per circle per launch.
extension BackendHydrator {
    /// Fetches the circle's SOS rows, upserts into SwiftData, and
    /// returns the notification identifiers for rows that transitioned
    /// from active to canceled. The caller retracts those after the
    /// hydration save commits, so a partial commit can't leave the
    /// local row showing canceled while the tray still alerts.
    func reconcileSOSEvents(
        circleId: UUID,
        modelContext: ModelContext
    ) async throws
        -> [String]
    {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return [] }

        let response: SOSEventsResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/sos",
            authenticated: true
        )
        let localMap = fetchLocalSOSMap(circleId: circleId, modelContext: modelContext)
        var insertedCount = 0
        var updatedCount = 0
        var retractIDs: [String] = []
        for dto in response.events {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id) else { continue }
            if let existing = localMap[dtoID] {
                // Snapshot before the mapper writes the new canceledAt
                // — otherwise wasActive would always be false on the
                // second cold-start after a cancellation.
                let wasActive = existing.canceledAt == nil
                let nowCanceled = dto.canceledAt != nil
                BackendHydratorMappers.updateSOSEvent(existing, from: dto, displayName: nil)
                if wasActive, nowCanceled {
                    retractIDs.append(BackendRealtimeClient.sosNotificationID(for: existing.id))
                }
                updatedCount += 1
            } else {
                let event = BackendHydratorMappers.makeSOSEvent(from: dto)
                event.circle = circle
                modelContext.insert(event)
                insertedCount += 1
            }
        }
        AppLogger.backend.info(
            "Reconciled SOS for \(circleId.uuidString, privacy: .public): +\(insertedCount, privacy: .public) ~\(updatedCount, privacy: .public) retract=\(retractIDs.count, privacy: .public)"
        )
        return retractIDs
    }

    /// Strips stale SOS time-sensitive notifications from both the
    /// delivered tray and the pending queue. Identifiers come from
    /// `BackendRealtimeClient.sosNotificationID(for:)` so this path,
    /// the realtime retract (Phase 25), and the original post (Phase
    /// 22) all key off the same string. Unknown identifiers are
    /// silently dropped by `UNUserNotificationCenter`.
    func retractStaleSOSNotifications(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        AppLogger.backend.info(
            "Hydrate: retracted \(identifiers.count, privacy: .public) stale SOS notification(s)"
        )
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
}
