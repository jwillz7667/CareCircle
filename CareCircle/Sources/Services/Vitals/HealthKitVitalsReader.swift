import Foundation
import HealthKit
import OSLog
import SwiftData

// MARK: - HealthKitVitalsReader

/// Reads new vitals samples from HealthKit since the last successful
/// import and writes them into the local SwiftData store + the Railway
/// backend (via `SyncEngine`).
///
/// **Scope.** Read-only in v1. CareCircle never writes back to HK —
/// caregiver-entered manual vitals stay scoped to CareCircle's own
/// store. The reader covers the eleven quantity kinds the app supports
/// plus aggregated nightly sleep, mapped from `HKCategorySample`s.
///
/// **Idempotency.** Each imported sample carries the HK `UUID` on the
/// `Vital` row. The backend has a unique index on `(circle_id,
/// healthkit_uuid)`; a re-import of the same sample falls through to
/// `replayed = true` and never duplicates. The local insert path
/// checks the same key before persisting, so multiple reader passes
/// on the same device are also safe.
///
/// **Incremental reads.** Each kind has its own anchor stored in
/// `UserDefaults`; we use `HKAnchoredObjectQueryDescriptor` so HK
/// hands us only samples added or deleted since the previous run.
/// Anchor persistence is per-circle so the same device managing
/// multiple Circles doesn't lose track of which samples have already
/// landed where (in practice we only support a single primary Circle
/// for v1, but the keying generalises).
///
/// **Authorization.** Callers must invoke `requestAuthorizationIfNeeded`
/// before the first read. Subsequent reads return silently if HK is
/// unavailable on this device class (e.g. iPad, Simulator) or the user
/// has not granted permission — `HKHealthStore.authorizationStatus`
/// only reports *write* authorization, so we treat "no samples
/// returned" as the expected outcome for denied reads.
@Observable
@MainActor
final class HealthKitVitalsReader {
    /// `(vital kind, HK quantity identifier, canonical unit, value scale)`.
    /// `scale` multiplies the HK quantity (in the canonical unit) before
    /// it lands in `Vital.valueNumeric`. For HK's percent type, samples
    /// arrive as 0.0–1.0, so we scale by 100 to get the user-facing 0–100.
    private static let quantityImports: [QuantityImport] = [
        .init(.heartRate, .heartRate, HKUnit.count().unitDivided(by: .minute()), 1),
        .init(.restingHeartRate, .restingHeartRate, HKUnit.count().unitDivided(by: .minute()), 1),
        .init(.bloodPressureSystolic, .bloodPressureSystolic, .millimeterOfMercury(), 1),
        .init(.bloodPressureDiastolic, .bloodPressureDiastolic, .millimeterOfMercury(), 1),
        .init(.bodyWeight, .bodyMass, .pound(), 1),
        .init(.bloodGlucose, .bloodGlucose, milligramPerDeciliter, 1),
        .init(.oxygenSaturation, .oxygenSaturation, .percent(), 100),
        .init(.bodyTemperature, .bodyTemperature, .degreeFahrenheit(), 1),
        .init(.respiratoryRate, .respiratoryRate, HKUnit.count().unitDivided(by: .minute()), 1),
        .init(.walkingSteadiness, .appleWalkingSteadiness, .percent(), 100),
        .init(.stepCount, .stepCount, .count(), 1),
        .init(.falls, .numberOfTimesFallen, .count(), 1),
    ]

    private static let milligramPerDeciliter: HKUnit =
        HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    private let store: HKHealthStore?
    private let anchors: HealthKitAnchorStore
    private let syncEngine: SyncEngine
    private let currentBackendUserID: @MainActor () -> String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    init(
        syncEngine: SyncEngine,
        currentBackendUserID: @escaping @MainActor () -> String?,
        userDefaults: UserDefaults = .standard
    ) {
        self.syncEngine = syncEngine
        self.currentBackendUserID = currentBackendUserID
        anchors = HealthKitAnchorStore(defaults: userDefaults)
        store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    /// Asks the user to grant read access to every kind the reader
    /// imports. Calling this when HK is unavailable returns `false`
    /// without surfacing an error — that's the correct outcome on
    /// Simulator and iPad. Re-prompting after a grant is harmless: HK
    /// shows the sheet exactly once per (type, app) and silently
    /// resolves on subsequent calls.
    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard let store else { return false }
        let readSet: Set<HKObjectType> = Set(
            Self.quantityImports.compactMap { HKObjectType.quantityType(forIdentifier: $0.identifier) }
                + [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)].compactMap(\.self)
        )
        do {
            try await store.requestAuthorization(toShare: [], read: readSet)
            AppLogger.healthKit.info("HK auth prompt resolved.")
            return true
        } catch {
            AppLogger.healthKit.error(
                "HK auth failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    /// Reads any HK samples added since the last anchor for the given
    /// `circle`, persists them as `Vital` rows, and enqueues them for
    /// upload via `SyncEngine`. Designed to be called on cold-start
    /// hydration and again on foreground transitions. Safe to invoke
    /// repeatedly — the local UUID check + backend dedupe keep duplicate
    /// inserts off the table.
    func readNewSamples(for circle: Circle, modelContext: ModelContext) async {
        guard let store else {
            AppLogger.healthKit.debug("HK reader skipped — health data unavailable on device.")
            return
        }
        guard let backendUserID = currentBackendUserID() else {
            AppLogger.healthKit.debug("HK reader skipped — no signed-in backend user.")
            return
        }
        let circleID = circle.id
        var importedCount = 0
        for spec in Self.quantityImports {
            importedCount += await ingestQuantity(
                spec,
                store: store,
                circle: circle,
                circleID: circleID,
                backendUserID: backendUserID,
                modelContext: modelContext
            )
        }
        importedCount += await ingestSleep(
            store: store,
            circle: circle,
            circleID: circleID,
            backendUserID: backendUserID,
            modelContext: modelContext
        )
        if importedCount > 0 {
            do {
                try modelContext.save()
            } catch {
                AppLogger.healthKit.error(
                    "HK reader failed to save context: \(String(describing: error), privacy: .public)"
                )
            }
        }
        AppLogger.healthKit.info(
            "HK reader: imported \(importedCount, privacy: .public) vitals row(s)."
        )
    }

    // MARK: - Quantity samples

    private func ingestQuantity(
        _ spec: QuantityImport,
        store: HKHealthStore,
        circle: Circle,
        circleID: UUID,
        backendUserID: String,
        modelContext: ModelContext
    ) async -> Int {
        guard let hkType = HKQuantityType.quantityType(forIdentifier: spec.identifier) else {
            return 0
        }
        let anchor = anchors.anchor(forKind: spec.kind, circleID: circleID)
        let predicate = HKSamplePredicate.quantitySample(type: hkType)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: anchor,
            limit: 250
        )
        let result: HKAnchoredObjectQueryDescriptor<HKQuantitySample>.Result
        do {
            result = try await descriptor.result(for: store)
        } catch {
            AppLogger.healthKit.notice(
                "HK quantity read failed (\(spec.kind.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)"
            )
            return 0
        }
        let existingUUIDs = fetchExistingHKUUIDs(
            for: spec.kind,
            circleID: circleID,
            modelContext: modelContext
        )
        var inserted = 0
        for sample in result.addedSamples {
            let key = sample.uuid.uuidString
            guard !existingUUIDs.contains(key) else { continue }
            let raw = sample.quantity.doubleValue(for: spec.unit)
            let scaled = raw * spec.scale
            let vital = Vital(
                kind: spec.kind,
                recordedAt: sample.startDate,
                valueNumeric: scaled,
                unit: spec.kind.defaultUnit,
                source: .healthkit,
                healthkitUUID: key,
                recordedByAppleUserID: backendUserID,
                recordedByDisplayName: ""
            )
            vital.circle = circle
            modelContext.insert(vital)
            syncEngine.enqueueVitalCreate(vital)
            inserted += 1
        }
        anchors.setAnchor(result.newAnchor, forKind: spec.kind, circleID: circleID)
        return inserted
    }

    // MARK: - Sleep aggregation

    /// Sleep samples are aggregated per local-night and emitted as a
    /// single `Vital` row per night with `valueNumeric` in hours. The
    /// row's `healthkitUUID` is a deterministic hash of the night's
    /// sample UUIDs so re-imports converge on the same row even when
    /// HK delivers the per-sample list in a different order.
    private func ingestSleep(
        store: HKHealthStore,
        circle: Circle,
        circleID: UUID,
        backendUserID: String,
        modelContext: ModelContext
    ) async -> Int {
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
                recordedByAppleUserID: backendUserID,
                recordedByDisplayName: ""
            )
            vital.circle = circle
            modelContext.insert(vital)
            syncEngine.enqueueVitalCreate(vital)
            inserted += 1
        }
        anchors.setAnchor(result.newAnchor, forKind: .sleepHours, circleID: circleID)
        return inserted
    }

    /// HK exposes a long-running history of sleep stages including
    /// `inBed`, `awake`, and several "asleep" variants. We count only
    /// asleep states toward nightly hours — `inBed` is a presence
    /// signal, not a duration of actual sleep.
    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
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

    private struct NightAggregate {
        let nightStart: Date
        let hours: Double
        let samples: [HKCategorySample]
    }

    /// Buckets asleep samples into "nights" keyed on the local-calendar
    /// day of the sample's *end* timestamp — most sleep crosses
    /// midnight, and end-day matches how a user would describe "last
    /// night's sleep" ("I slept 7 hours" usually means "for the
    /// morning of the 5th, I had 7 hours").
    private static func aggregateSleepByNight(
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
                    hours: seconds / 3600.0,
                    samples: samples
                )
            }
    }

    /// Deterministic key for a night's row. Stable across reruns as
    /// long as the same set of HK sample UUIDs participate. If HK
    /// adds a new sample to an already-recorded night, the key
    /// changes and a new row lands — UI ordering keeps both visible
    /// until cold-start hydration reconciles. Acceptable noise for v1.
    private static func sleepDedupeKey(
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

    // MARK: - Local lookup

    /// Fetches every `healthkitUUID` already present on the local
    /// store for the given kind + circle, so the importer can skip
    /// inserts that would otherwise just race the backend dedupe.
    private func fetchExistingHKUUIDs(
        for kind: VitalKind,
        circleID: UUID,
        modelContext: ModelContext
    )
        -> Set<String>
    {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<Vital>(
            predicate: #Predicate { vital in
                vital.kindRaw == kindRaw && vital.healthkitUUID != nil
            }
        )
        guard let rows = try? modelContext.fetch(descriptor) else { return [] }
        return Set(
            rows.compactMap { row in
                row.circle?.id == circleID ? row.healthkitUUID : nil
            }
        )
    }
}

// MARK: - QuantityImport

private struct QuantityImport {
    let kind: VitalKind
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let scale: Double

    init(
        _ kind: VitalKind,
        _ identifier: HKQuantityTypeIdentifier,
        _ unit: HKUnit,
        _ scale: Double
    ) {
        self.kind = kind
        self.identifier = identifier
        self.unit = unit
        self.scale = scale
    }
}
