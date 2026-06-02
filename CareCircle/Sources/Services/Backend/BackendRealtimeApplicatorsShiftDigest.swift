import Foundation
import OSLog
import SwiftData

// MARK: - Phase 30 applicator (shift digests)

/// Realtime applicator for `shift_digests`. The endpoint is
/// cursor-paginated (the same shape as activities), so the applicator
/// refetches the most recent page and upserts into SwiftData without
/// asserting authoritative deletes — "absent from response" cannot be
/// distinguished from "rolled off the page." Soft-delete propagation
/// for older digests is owned by cold-start hydration (Phase 30B
/// hydrator) and the future full-merge pass.
///
/// Display names are intentionally left blank at insert time. The
/// detail/row views look up `narratorAppleUserID` against the local
/// `Member` store to resolve a display name (same convention as
/// `Activity.authorAppleUserID`), so a digest broadcast that arrives
/// before the member roster is hydrated still renders correctly once
/// the members sync settles.
extension BackendRealtimeClient {
    func applyShiftDigestChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else {
            AppLogger.backend.debug(
                "Realtime: shift-digest change for unknown circle \(circleId.uuidString, privacy: .public)"
            )
            return
        }
        let response: ShiftDigestsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/digests?limit=20",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "shift-digests", error: error)
            return
        }
        upsertList(
            response.digests,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "shift-digests",
                deleteAbsent: false,
                localPredicate: #Predicate<ShiftDigest> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeShiftDigest(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateShiftDigest(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
    }
}
