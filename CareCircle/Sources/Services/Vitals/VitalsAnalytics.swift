import Foundation

// MARK: - VitalsAnalytics

/// Pure on-device statistics over a Circle's `Vital` history. We
/// compute per-kind baseline mean + stddev across a rolling window,
/// then z-score the most recent reading against it. Anything beyond
/// ±2σ counts as anomalous and surfaces in the live monitor.
///
/// All math is local — no PHI leaves the device. The output is a
/// value-typed summary the UI can render without keeping references
/// back to `@Model` rows (`Vital` is intentionally not `Sendable`).
@MainActor
enum VitalsAnalytics {
    /// Rolling window for baselines + sparkline.
    static let baselineWindowDays = 14
    /// Z-score absolute threshold for "anomalous".
    static let anomalyZScore = 2.0
    /// Minimum samples needed before we trust the baseline. Below
    /// this we still render the latest reading but suppress the
    /// anomaly flag — two readings can't form a meaningful σ.
    static let minBaselineSamples = 4
    /// Sparkline cap so a chatty kind (HR every minute from Watch)
    /// doesn't blow up render cost.
    static let maxSparklinePoints = 60

    struct KindSummary: Identifiable, Sendable {
        let kind: VitalKind
        let latest: LatestReading?
        let baseline: Baseline?
        let trend: TrendDirection
        let trendDeltaPercent: Double?
        let isAnomalous: Bool
        let zScore: Double?
        let sparkline: [SparklinePoint]
        let sampleCount: Int

        var id: VitalKind {
            kind
        }

        var hasData: Bool {
            latest != nil
        }
    }

    struct LatestReading: Sendable {
        let value: Double
        let unit: String
        let recordedAt: Date
        let source: VitalSource
    }

    struct Baseline: Sendable {
        let mean: Double
        let stdDev: Double
        let sampleCount: Int
    }

    struct SparklinePoint: Identifiable, Sendable {
        let date: Date
        let value: Double
        var id: TimeInterval {
            date.timeIntervalSince1970
        }
    }

    enum TrendDirection: Sendable {
        case rising, falling, flat, unknown

        var systemImage: String {
            switch self {
            case .rising: "arrow.up.right"
            case .falling: "arrow.down.right"
            case .flat: "arrow.right"
            case .unknown: "minus"
            }
        }
    }

    /// Summarizes the provided vitals across the requested kinds.
    /// Blood pressure is intentionally split per-row at the model
    /// layer — UI pairs systolic + diastolic at render time.
    static func summarize(
        vitals: [Vital],
        kinds: [VitalKind] = VitalKind.allCases,
        now: Date = .now
    )
        -> [KindSummary]
    {
        let cutoff = now.addingTimeInterval(-Double(baselineWindowDays) * 86_400)
        let byKind = Dictionary(grouping: vitals) { $0.kind }
        return kinds.map { kind -> KindSummary in
            let rows = (byKind[kind] ?? [])
                .filter { $0.valueNumeric != nil }
                .sorted { $0.recordedAt < $1.recordedAt }
            return summarizeKind(kind: kind, rows: rows, cutoff: cutoff)
        }
    }

    private static func summarizeKind(
        kind: VitalKind,
        rows: [Vital],
        cutoff: Date
    )
        -> KindSummary
    {
        guard let latestRow = rows.last, let latestValue = latestRow.valueNumeric else {
            return KindSummary(
                kind: kind,
                latest: nil,
                baseline: nil,
                trend: .unknown,
                trendDeltaPercent: nil,
                isAnomalous: false,
                zScore: nil,
                sparkline: [],
                sampleCount: 0
            )
        }
        let windowed = rows.filter { $0.recordedAt >= cutoff }
        let values = windowed.compactMap(\.valueNumeric)
        let baseline = computeBaseline(values: values)
        let zScore = baseline.flatMap { base in
            base.stdDev > 0.0001 ? (latestValue - base.mean) / base.stdDev : nil
        }
        let isAnomalous: Bool = {
            guard let z = zScore, let base = baseline,
                  base.sampleCount >= minBaselineSamples else { return false }
            return abs(z) >= anomalyZScore
        }()
        let trend = computeTrend(rows: windowed, latestValue: latestValue)
        let sparkline = sparklinePoints(rows: windowed)
        return KindSummary(
            kind: kind,
            latest: LatestReading(
                value: latestValue,
                unit: latestRow.unit.isEmpty ? kind.defaultUnit : latestRow.unit,
                recordedAt: latestRow.recordedAt,
                source: latestRow.source
            ),
            baseline: baseline,
            trend: trend.direction,
            trendDeltaPercent: trend.deltaPercent,
            isAnomalous: isAnomalous,
            zScore: zScore,
            sparkline: sparkline,
            sampleCount: rows.count
        )
    }

    private static func computeBaseline(values: [Double]) -> Baseline? {
        guard values.count >= 2 else { return nil }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) } / n
        return Baseline(mean: mean, stdDev: sqrt(variance), sampleCount: values.count)
    }

    private struct TrendComputation {
        let direction: TrendDirection
        let deltaPercent: Double?
    }

    /// Splits the windowed rows into "earlier half" vs "later half" by
    /// time and compares means. More robust than slope-fit at small
    /// sample counts and trivial to render as a delta% chip.
    private static func computeTrend(rows: [Vital], latestValue: Double) -> TrendComputation {
        let values = rows.compactMap(\.valueNumeric)
        guard values.count >= minBaselineSamples else {
            return TrendComputation(direction: .unknown, deltaPercent: nil)
        }
        let mid = values.count / 2
        let earlier = Array(values.prefix(mid))
        let later = Array(values.suffix(values.count - mid))
        guard !earlier.isEmpty, !later.isEmpty else {
            return TrendComputation(direction: .unknown, deltaPercent: nil)
        }
        let earlierMean = earlier.reduce(0, +) / Double(earlier.count)
        let laterMean = later.reduce(0, +) / Double(later.count)
        guard earlierMean.magnitude > 0.0001 else {
            return TrendComputation(direction: .flat, deltaPercent: 0)
        }
        let delta = (laterMean - earlierMean) / earlierMean
        let direction: TrendDirection = if abs(delta) < 0.02 {
            .flat
        } else if delta > 0 {
            .rising
        } else {
            .falling
        }
        _ = latestValue
        return TrendComputation(direction: direction, deltaPercent: delta * 100)
    }

    private static func sparklinePoints(rows: [Vital]) -> [SparklinePoint] {
        let mapped = rows.compactMap { row -> SparklinePoint? in
            guard let value = row.valueNumeric else { return nil }
            return SparklinePoint(date: row.recordedAt, value: value)
        }
        guard mapped.count > maxSparklinePoints else { return mapped }
        // Downsample by stride so we keep the chronological shape
        // without ballooning Chart cost on chatty kinds.
        let stride = Int(ceil(Double(mapped.count) / Double(maxSparklinePoints)))
        return mapped.enumerated()
            .filter { $0.offset.isMultiple(of: stride) }
            .map(\.element)
    }

    // MARK: - Wellness composite

    /// Composite 0–100 score for the "today's wellbeing" hero ring.
    /// Driven by (a) anomaly load — every anomalous kind drags the
    /// score — and (b) whether the latest reading per kind sits inside
    /// the kind's sanity range. Heuristic, not medical. Refined by the
    /// later AI insights engine.
    static func wellnessScore(from summaries: [KindSummary]) -> Int? {
        let present = summaries.filter(\.hasData)
        guard !present.isEmpty else { return nil }
        var score = 100.0
        for s in present {
            if s.isAnomalous {
                let zMagnitude = abs(s.zScore ?? anomalyZScore)
                let penalty = min(20.0, (zMagnitude - anomalyZScore) * 6 + 8)
                score -= penalty
            }
            if let latest = s.latest, !s.kind.sanityRange.contains(latest.value) {
                score -= 6
            }
        }
        return max(0, min(100, Int(score.rounded())))
    }
}
