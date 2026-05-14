import Foundation
import OSLog
import SwiftData

// MARK: - UpsertSpec

/// Configuration + closures that drive an applicator's upsert pass.
/// Bundling them keeps `upsertList`'s parameter list at three params
/// (response, spec, modelContext) instead of ten, and groups the
/// per-domain knobs in one place at every call site.
struct UpsertSpec<M: PersistentModel & Identifiable, DTO> where M.ID == UUID {
    let circle: Circle
    let circleId: UUID
    let domain: String
    let deleteAbsent: Bool
    let circleIDOf: (M) -> UUID?
    let parseID: (DTO) -> UUID?
    let insert: (DTO, Circle) -> M
    let update: (M, DTO) -> Void
}

extension BackendRealtimeClient {
    /// Upsert + soft-delete merge used by every list-refetch applicator.
    /// Updates fields on existing local rows, inserts unknown rows, and
    /// (when `spec.deleteAbsent` is true) removes local rows whose UUIDs
    /// no longer appear in the backend response — that's how soft-deletes
    /// propagate via the realtime path for non-paginated domains.
    func upsertList<M: PersistentModel & Identifiable, DTO>(
        _ response: [DTO],
        spec: UpsertSpec<M, DTO>,
        modelContext: ModelContext
    ) where M.ID == UUID {
        let localMap = buildLocalMap(modelContext: modelContext, spec: spec)
        var responseIDs: Set<UUID> = []
        var inserted = 0
        var updated = 0
        for dto in response {
            guard let id = spec.parseID(dto) else { continue }
            responseIDs.insert(id)
            if let existing = localMap[id] {
                spec.update(existing, dto)
                updated += 1
            } else {
                let row = spec.insert(dto, spec.circle)
                modelContext.insert(row)
                inserted += 1
            }
        }
        var deleted = 0
        if spec.deleteAbsent {
            for (id, row) in localMap where !responseIDs.contains(id) {
                modelContext.delete(row)
                deleted += 1
            }
        }
        guard inserted + updated + deleted > 0 else { return }
        saveUpsert(
            modelContext: modelContext,
            domain: spec.domain,
            circleId: spec.circleId,
            inserted: inserted,
            updated: updated,
            deleted: deleted
        )
    }

    private func buildLocalMap<M: PersistentModel & Identifiable>(
        modelContext: ModelContext,
        spec: UpsertSpec<M, some Any>
    )
        -> [UUID: M] where M.ID == UUID
    {
        let all = (try? modelContext.fetch(FetchDescriptor<M>())) ?? []
        var map: [UUID: M] = [:]
        for row in all where spec.circleIDOf(row) == spec.circleId {
            map[row.id] = row
        }
        return map
    }

    private func saveUpsert(
        modelContext: ModelContext,
        domain: String,
        circleId: UUID,
        inserted: Int,
        updated: Int,
        deleted: Int
    ) {
        let circleIdString = circleId.uuidString
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: \(domain, privacy: .public) for \(circleIdString, privacy: .public): +\(inserted, privacy: .public) ~\(updated, privacy: .public) -\(deleted, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after \(domain, privacy: .public) merge: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
