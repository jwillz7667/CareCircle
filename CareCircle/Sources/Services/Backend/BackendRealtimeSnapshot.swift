import Foundation
import OSLog
import SwiftData

// MARK: - Snapshot-on-reconnect resync

/// Phase 24's gap-resync pass. Runs after every WebSocket reconnect
/// (every `subscribed` frame *after* the first one) so changes that
/// landed on the backend while this client was disconnected are
/// reconciled into SwiftData without waiting for cold-start hydration.
///
/// The implementation is just "call every list-shaped applicator
/// across every subscribed circle in parallel." Each applicator is
/// already idempotent (Phase 23's upsert + soft-delete merge), so the
/// snapshot is correct end-to-end with no per-domain customization.
///
/// Doses are skipped because the dose endpoint is per-row — there's
/// no list to refetch. Stale dose rows are usually corrected by the
/// medication applicator's cascade-delete or by the next user-driven
/// dose mutation; the residual window (a status change for a row
/// whose parent medication did not change, missed during disconnect)
/// is a Phase 25+ candidate.
extension BackendRealtimeClient {
    /// Fans out the eight list-shaped applicators across the supplied
    /// circle IDs. Awaits all in-flight tasks before returning so the
    /// caller can observe `isResyncing` flipping back to `false` only
    /// when the pass is fully drained.
    func snapshotResync(
        circleIds: [UUID],
        modelContext: ModelContext
    ) async {
        isResyncing = true
        let circleCount = circleIds.count
        AppLogger.backend.info(
            "Realtime: snapshot resync starting for \(circleCount, privacy: .public) circle(s)"
        )
        await withTaskGroup(of: Void.self) { group in
            for circleId in circleIds {
                addSnapshotTasks(group: &group, circleId: circleId, modelContext: modelContext)
            }
        }
        lastResyncAt = .now
        isResyncing = false
        AppLogger.backend.info(
            "Realtime: snapshot resync complete for \(circleCount, privacy: .public) circle(s)"
        )
    }

    private func addSnapshotTasks(
        group: inout TaskGroup<Void>,
        circleId: UUID,
        modelContext: ModelContext
    ) {
        group.addTask { [weak self] in
            await self?.applyActivityChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyMedicationChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyAppointmentChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyMemberChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyEmergencyContactChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyDocumentChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applySosChange(circleId: circleId, modelContext: modelContext)
        }
        group.addTask { [weak self] in
            await self?.applyCareMinuteChange(circleId: circleId, modelContext: modelContext)
        }
    }
}
