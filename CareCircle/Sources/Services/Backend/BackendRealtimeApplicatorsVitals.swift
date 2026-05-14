import Foundation
import OSLog
import SwiftData

// MARK: - Phase 33 applicator (vitals)

/// Realtime applicator for `vitals`. The list endpoint is
/// cursor-paginated, so the applicator refetches the most recent page
/// (`limit=50`) and upserts into SwiftData without asserting
/// authoritative deletes. "Absent from response" cannot be
/// distinguished from "rolled off the page" — soft-delete propagation
/// for older vitals is owned by cold-start hydration.
///
/// Display names for `recordedByUserId` are resolved lazily by row
/// views against the local `Member` store (same convention as
/// activities/digests), so a vital broadcast that arrives before the
/// members roster is hydrated still renders correctly once the member
/// sync settles.
extension BackendRealtimeClient {
    func applyVitalChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else {
            AppLogger.backend.debug(
                "Realtime: vital change for unknown circle \(circleId.uuidString, privacy: .public)"
            )
            return
        }
        let response: VitalsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/vitals?limit=50",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "vitals", error: error)
            return
        }
        upsertList(
            response.vitals,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "vitals",
                deleteAbsent: false,
                circleIDOf: { (row: Vital) in row.circle?.id },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeVital(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateVital(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
    }
}
