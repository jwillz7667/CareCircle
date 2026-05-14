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

    private static let milligramPerDeciliter =
        HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    private let store: HKHealthStore?
    /// Internal (not `private`) so the sleep extension in
    /// `HealthKitVitalsReader+Sleep.swift` can read/write its own
    /// per-kind anchor. Same applies to `syncEngine` below.
    let anchors: HealthKitAnchorStore
    let syncEngine: SyncEngine
    private let currentRecorderAppleUserID: @MainActor () -> String?

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(
        syncEngine: SyncEngine,
        currentRecorderAppleUserID: @escaping @MainActor () -> String?,
        userDefaults: UserDefaults = .standard
    ) {
        self.syncEngine = syncEngine
        self.currentRecorderAppleUserID = currentRecorderAppleUserID
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
        guard let appleUserID = currentRecorderAppleUserID() else {
            AppLogger.healthKit.debug("HK reader skipped — no signed-in user to attribute samples to.")
            return
        }
        let recorder = RecorderContext(
            appleUserID: appleUserID,
            displayName: resolveRecorderDisplayName(appleUserID: appleUserID, circle: circle)
        )
        let circleID = circle.id
        var importedCount = 0
        for spec in Self.quantityImports {
            importedCount += await ingestQuantity(
                spec,
                store: store,
                circle: circle,
                circleID: circleID,
                recorder: recorder,
                modelContext: modelContext
            )
        }
        importedCount += await ingestSleep(
            store: store,
            circle: circle,
            circleID: circleID,
            recorder: recorder,
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
        recorder: RecorderContext,
        modelContext: ModelContext
    ) async
        -> Int
    {
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
                recordedByAppleUserID: recorder.appleUserID,
                recordedByDisplayName: recorder.displayName
            )
            vital.circle = circle
            modelContext.insert(vital)
            syncEngine.enqueueVitalCreate(vital)
            inserted += 1
        }
        anchors.setAnchor(result.newAnchor, forKind: spec.kind, circleID: circleID)
        return inserted
    }

    /// Looks up the display name to stamp on an imported row from the
    /// Circle's `members` list so HK-imported rows render with the same
    /// name as the caregiver's manual entries. Falls back to empty when
    /// the recorder hasn't been added as a member yet — `VitalsListView`
    /// then resolves the name from the live `Circle.members` query.
    private func resolveRecorderDisplayName(
        appleUserID: String,
        circle: Circle
    )
        -> String
    {
        circle.members
            .first(where: { $0.appleUserID == appleUserID })?
            .displayName ?? ""
    }

    // MARK: - Local lookup

    /// Fetches every `healthkitUUID` already present on the local
    /// store for the given kind + circle, so the importer can skip
    /// inserts that would otherwise just race the backend dedupe.
    /// Internal (not `private`) so the sleep extension can reuse it.
    func fetchExistingHKUUIDs(
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

// MARK: - RecorderContext

/// Bundles the recorder identity stamped onto every imported `Vital`.
/// Internal (not file-private) so the sleep-aggregation extension in
/// `HealthKitVitalsReader+Sleep.swift` can use the same type.
struct RecorderContext {
    let appleUserID: String
    let displayName: String
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
