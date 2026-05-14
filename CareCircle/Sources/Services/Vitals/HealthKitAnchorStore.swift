import Foundation
import HealthKit
import OSLog

// MARK: - HealthKitAnchorStore

/// Persists `HKQueryAnchor`s in `UserDefaults` so `HKAnchoredObjectQuery`
/// runs see only new/changed samples on each invocation.
///
/// Keys are scoped by `(VitalKind, Circle)` because the same device may
/// be a member of multiple Circles in the future; replaying a HK
/// sample stream into a fresh Circle should start from the beginning
/// even if the user has already imported their entire history into
/// another one.
///
/// Anchors are encoded with `NSKeyedArchiver` since that's the
/// archiving the HK headers themselves use, and it round-trips cleanly
/// across iOS upgrades. A decode failure returns `nil` and the next
/// query falls back to "every sample since the dawn of time," which is
/// the right behavior — duplicates are caught downstream by the
/// `(circle, healthkit_uuid)` unique key.
nonisolated final class HealthKitAnchorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func anchor(forKind kind: VitalKind, circleID: UUID) -> HKQueryAnchor? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: key(forKind: kind, circleID: circleID)) else {
            return nil
        }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self,
                from: data
            )
        } catch {
            AppLogger.healthKit.error(
                "Anchor decode failed for \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func setAnchor(_ anchor: HKQueryAnchor, forKind kind: VitalKind, circleID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: anchor,
                requiringSecureCoding: true
            )
            defaults.set(data, forKey: key(forKind: kind, circleID: circleID))
        } catch {
            AppLogger.healthKit.error(
                "Anchor encode failed for \(kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Drops every persisted anchor for the given circle. Called from
    /// the debug pane (and, eventually, from a "leave circle" action)
    /// so the next read sweeps the full HK history fresh — useful when
    /// a re-import is needed to backfill rows that never made it to
    /// the backend.
    func reset(forCircleID circleID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        for kind in VitalKind.allCases {
            defaults.removeObject(forKey: key(forKind: kind, circleID: circleID))
        }
    }

    private func key(forKind kind: VitalKind, circleID: UUID) -> String {
        "healthkit.anchor.\(circleID.uuidString).\(kind.rawValue)"
    }
}
