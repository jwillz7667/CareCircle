import Foundation
import HealthKit
import OSLog
import SwiftData

// MARK: - HealthKitVitalsReader + Sleep

/// Sleep aggregation pulled into a sibling extension so the core
/// `HealthKitVitalsReader` stays focused on the quantity-import loop.
/// Sleep is a different shape from the eleven quantity kinds: HK emits
/// per-stage segments throughout the night, and we need to roll them
/// up into a single hours-asleep number per local night for the
/// caregiver feed.
extension HealthKitVitalsReader {
    /// Sleep samples are aggregated per local-night and emitted as a
    /// single `Vital` row per night with `valueNumeric` in hours. The
    /// row's `healthkitUUID` is a deterministic hash of the night's
    /// sample UUIDs so re-imports converge on the same row even when
    /// HK delivers the per-sample list in a different order.
    func ingestSleep(
        store: HKHealthStore,
        circle: Circle,
        circleID: UUID,
        recorder: RecorderContext,
        modelContext: ModelContext
    ) async
        -> Int
    {
        guard let hkType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return 0
        }
        let anchor = anchors.anchor(forKind: .sleepHours, circleID: circleID)
        let predicate = HKSamplePredicate.categorySample(type: hkType)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: anchor,
            limit: 500
        )
        let result: HKAnchoredObjectQueryDescriptor<HKCategorySample>.Result
        do {
            result = try await descriptor.result(for: store)
        } catch {
            AppLogger.healthKit.notice(
                "HK sleep read failed: \(String(describing: error), privacy: .public)"
            )
            return 0
        }
        let asleepSamples = result.addedSamples.filter(Self.isAsleep)
        let perNight = Self.aggregateSleepByNight(asleepSamples)
        let existingUUIDs = fetchExistingHKUUIDs(
            for: .sleepHours,
            circleID: circleID,
            modelContext: modelContext
        )
        let inserted = persistSleepRows(
            perNight: perNight,
            existingUUIDs: existingUUIDs,
            circle: circle,
            recorder: recorder,
            modelContext: modelContext
        )
        anchors.setAnchor(result.newAnchor, forKind: .sleepHours, circleID: circleID)
        return inserted
    }

    private func persistSleepRows(
        perNight: [NightAggregate],
        existingUUIDs: Set<String>,
        circle: Circle,
        recorder: RecorderContext,
        modelContext: ModelContext
    )
        -> Int
    {
        var inserted = 0
        for night in perNight {
            let dedupeKey = Self.sleepDedupeKey(forNight: night.nightStart, samples: night.samples)
            guard !existingUUIDs.contains(dedupeKey) else { continue }
            let vital = Vital(
                kind: .sleepHours,
                recordedAt: night.nightStart,
                valueNumeric: night.hours,
                unit: VitalKind.sleepHours.defaultUnit,
                source: .healthkit,
                healthkitUUID: dedupeKey,
                recordedByAppleUserID: recorder.appleUserID,
                recordedByDisplayName: recorder.displayName
            )
            vital.circle = circle
            modelContext.insert(vital)
            syncEngine.enqueueVitalCreate(vital)
            inserted += 1
        }
        return inserted
    }

    /// HK exposes a long-running history of sleep stages including
    /// `inBed`, `awake`, and several "asleep" variants. We count only
    /// asleep states toward nightly hours — `inBed` is a presence
    /// signal, not a duration of actual sleep.
    static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            true
        default:
            false
        }
    }

    /// Buckets asleep samples into "nights" keyed on the local-calendar
    /// day of the sample's *end* timestamp — most sleep crosses
    /// midnight, and end-day matches how a user would describe "last
    /// night's sleep" ("I slept 7 hours" usually means "for the
    /// morning of the 5th, I had 7 hours").
    static func aggregateSleepByNight(
        _ samples: [HKCategorySample]
    )
        -> [NightAggregate]
    {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.endDate)
        }
        return grouped
            .sorted(by: { $0.key < $1.key })
            .map { nightStart, samples in
                let seconds = samples.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                return NightAggregate(
                    nightStart: nightStart,
                    hours: seconds / 3_600.0,
                    samples: samples
                )
            }
    }

    /// Deterministic key for a night's row. Stable across reruns as
    /// long as the same set of HK sample UUIDs participate. If HK
    /// adds a new sample to an already-recorded night, the key
    /// changes and a new row lands — UI ordering keeps both visible
    /// until cold-start hydration reconciles. Acceptable noise for v1.
    static func sleepDedupeKey(
        forNight night: Date,
        samples: [HKCategorySample]
    )
        -> String
    {
        let sortedIDs = samples.map(\.uuid.uuidString).sorted()
        let joined = sortedIDs.joined(separator: "|")
        let nightStamp = Int(night.timeIntervalSince1970)
        return "sleep:\(nightStamp):\(joined.hashValue)"
    }
}

// MARK: - NightAggregate

/// Per-local-night roll-up of asleep `HKCategorySample`s. Lives at
/// file scope (internal) so the extension and the future tests in
/// `CareCircleTests/Unit/Vitals/` can share the shape without the
/// reader exposing it across the whole module.
struct NightAggregate {
    let nightStart: Date
    let hours: Double
    let samples: [HKCategorySample]
}
