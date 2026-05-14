import Foundation

// MARK: - DerivedInsight

/// Transient value type emitted by an `InsightPattern`. The engine maps
/// it to a persisted `Insight` row by `dedupeKey` so that pattern
/// detectors stay pure functions of the input circle and don't have
/// to touch SwiftData themselves.
nonisolated struct DerivedInsight: Sendable, Hashable {
    let kind: InsightKind
    let severity: InsightSeverity
    let subjectKind: InsightSubjectKind
    let subjectId: UUID?
    let title: String
    let body: String
    let payloadJSON: String?

    var dedupeKey: String {
        Insight.dedupeKey(kind: kind, subjectKind: subjectKind, subjectId: subjectId)
    }
}

// MARK: - InsightPattern

/// A pure function from a `Circle`'s current state to the set of
/// `DerivedInsight`s it implies. Patterns must be deterministic —
/// running `derive` twice on the same input must produce the same
/// output — because the engine relies on stable `dedupeKey`s across
/// recomputes to preserve dismissals.
@MainActor
protocol InsightPattern: Sendable {
    var kind: InsightKind { get }
    func derive(from circle: Circle) -> [DerivedInsight]
}
