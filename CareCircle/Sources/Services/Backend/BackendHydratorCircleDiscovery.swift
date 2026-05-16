import Foundation
import OSLog
import SwiftData

// MARK: - Circle discovery

/// Returning a user to their existing Circles after a reinstall (or any
/// other fresh-SwiftData event — new device, "Reset CloudKit", logout +
/// login on the same device) means we can't wait for cold-start
/// per-domain hydration: every per-domain helper bails when the local
/// `Circle` row is missing, so we'd never insert anything.
///
/// `discoverCircles` does the missing first step. It asks the backend
/// which Circles the signed-in user can see and materializes any that
/// aren't already in SwiftData, copying the authoritative subscription
/// columns along the way so the paywall / seat-cap gates don't flicker
/// from `.free` while the dedicated subscription hydrator catches up.
///
/// `ownerAppleUserID` is heterogeneous in v1 — for Apple sessions we
/// store the Apple credential, for email/Google we store the backend
/// UUID. We resolve that by writing the *viewer's* local id if the
/// backend tells us this viewer owns the Circle, and the backend's
/// `ownerUserId` otherwise (a UUID that won't collide with the viewer's
/// id, which is the right outcome for "joined as a member").
extension BackendHydrator {
    /// Pulls every Circle visible to the signed-in user and inserts any
    /// not already represented locally. Idempotent — a second pass
    /// matches existing rows by `id` and updates only the subscription
    /// columns + name.
    ///
    /// - Parameters:
    ///   - viewerLocalID: `SignedInUser.id`. Written into
    ///     `Circle.ownerAppleUserID` for Circles this viewer owns so the
    ///     existing `activeCircle` equality check keeps working.
    ///   - viewerBackendID: backend UUID returned by `/v1/me`. Used only
    ///     to decide ownership for the row above.
    func discoverCircles(
        viewerLocalID: String,
        viewerBackendID: String,
        modelContext: ModelContext
    ) async {
        do {
            let response: CircleSummariesResponse = try await apiClient.send(
                method: .get,
                path: "/v1/circles",
                authenticated: true
            )

            var inserted = 0
            var updated = 0
            for summary in response.circles {
                guard let parsedID = BackendHydratorMappers.parseUUID(summary.id) else {
                    AppLogger.backend.error(
                        "Skipping circle with unparseable id \(summary.id, privacy: .public)"
                    )
                    continue
                }

                if let existing = fetchCircle(id: parsedID, modelContext: modelContext) {
                    applyBackendState(summary, to: existing)
                    updated += 1
                    continue
                }

                let ownerIdentifier = summary.ownerUserId == viewerBackendID
                    ? viewerLocalID
                    : summary.ownerUserId
                let circle = Circle(
                    id: parsedID,
                    name: summary.name,
                    ownerAppleUserID: ownerIdentifier,
                    createdAt: summary.createdAt
                )
                applyBackendState(summary, to: circle)
                modelContext.insert(circle)
                inserted += 1
            }

            if inserted > 0 || updated > 0 {
                try modelContext.save()
            }
            AppLogger.backend.info(
                "Circle discovery complete — inserted=\(inserted, privacy: .public) updated=\(updated, privacy: .public)."
            )
        } catch let error as APIError {
            AppLogger.backend.error(
                "Circle discovery failed: \(String(describing: error), privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Circle discovery failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func applyBackendState(_ summary: CircleSummaryDTO, to circle: Circle) {
        circle.name = summary.name
        circle.subscriptionTierRaw = summary.subscriptionTier
        circle.subscriptionStatusRaw = summary.subscriptionStatus
    }
}
