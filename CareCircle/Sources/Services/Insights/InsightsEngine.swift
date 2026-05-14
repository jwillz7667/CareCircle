import Foundation
import OSLog
import SwiftData

// MARK: - InsightsEngine

/// Orchestrates the recompute pass across all registered patterns and
/// persists the result. Lives as a single `@Observable` instance
/// injected through the SwiftUI environment so views can observe
/// `lastRecomputedAt` and trigger explicit recomputes.
///
/// The engine is per-device. Insights it writes are not synced to
/// CloudKit or to the Railway backend — different caregivers in the
/// same Circle may find different observations relevant, and we'd
/// rather show each member their own dismissal state than synchronize
/// a noisy stream of derived facts.
@Observable
@MainActor
final class InsightsEngine {
    private(set) var lastRecomputedAt: Date?
    private(set) var lastError: String?

    private let patterns: [any InsightPattern]
    private let debouncer = TaskDebouncer(delay: .seconds(5))

    init(patterns: [any InsightPattern]? = nil) {
        self.patterns = patterns ?? InsightsEngine.defaultPatterns
    }

    static var defaultPatterns: [any InsightPattern] {
        [DoseTimingDriftPattern(), MissedDoseRiskPattern()]
    }

    // MARK: Public API

    /// Runs every pattern over `circle`'s current state, upserts the
    /// derived insights, and archives any previously-emitted rows
    /// that this pass no longer surfaces.
    func recompute(circle: Circle, modelContext: ModelContext) {
        let derived = patterns.flatMap { $0.derive(from: circle) }
        let currentKeys = Set(derived.map(\.dedupeKey))

        upsert(derived, circle: circle, modelContext: modelContext)
        archiveStale(currentKeys: currentKeys, circle: circle, modelContext: modelContext)

        do {
            try modelContext.save()
            lastRecomputedAt = .now
            lastError = nil
            AppLogger.app.info(
                "Insights recomputed: \(derived.count, privacy: .public) derived, \(currentKeys.count, privacy: .public) active."
            )
        } catch {
            lastError = error.localizedDescription
            AppLogger.app.error(
                "Failed to persist insights recompute: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Schedules a debounced recompute. Multiple rapid calls collapse
    /// to a single execution five seconds after the last call.
    func recomputeDebounced(circle: Circle, modelContext: ModelContext) {
        debouncer.schedule { [weak self] in
            self?.recompute(circle: circle, modelContext: modelContext)
        }
    }

    /// Dismisses an insight. Dismissals are permanent for the same
    /// `dedupeKey` — if the same observation re-emerges later the
    /// engine respects the existing dismissed row and does not
    /// resurface it.
    func dismiss(_ insight: Insight, modelContext: ModelContext) {
        insight.dismissedAt = .now
        try? modelContext.save()
    }

    /// Marks an insight as applied (the user took the suggested
    /// action). Applied rows archive the same way dismissed rows do.
    func markApplied(_ insight: Insight, modelContext: ModelContext) {
        insight.appliedAt = .now
        try? modelContext.save()
    }

    // MARK: Reconciliation

    private func upsert(
        _ derived: [DerivedInsight],
        circle: Circle,
        modelContext: ModelContext
    ) {
        let existing = fetchExisting(circle: circle, modelContext: modelContext)
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.dedupeKey, $0) })

        for item in derived {
            if let row = byKey[item.dedupeKey] {
                row.title = item.title
                row.body = item.body
                row.severityRaw = item.severity.rawValue
                row.payloadJSON = item.payloadJSON
                row.computedAt = .now
            } else {
                let row = Insight(
                    kind: item.kind,
                    severity: item.severity,
                    subjectKind: item.subjectKind,
                    subjectId: item.subjectId,
                    title: item.title,
                    body: item.body,
                    dedupeKey: item.dedupeKey,
                    payloadJSON: item.payloadJSON
                )
                row.circle = circle
                modelContext.insert(row)
                byKey[item.dedupeKey] = row
            }
        }
    }

    private func archiveStale(
        currentKeys: Set<String>,
        circle: Circle,
        modelContext: ModelContext
    ) {
        for row in fetchExisting(circle: circle, modelContext: modelContext)
            where !currentKeys.contains(row.dedupeKey)
            && row.appliedAt == nil
            && row.dismissedAt == nil
        {
            row.appliedAt = .now
        }
    }

    private func fetchExisting(circle: Circle, modelContext: ModelContext) -> [Insight] {
        let circleId = circle.id
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.circle?.id == circleId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
