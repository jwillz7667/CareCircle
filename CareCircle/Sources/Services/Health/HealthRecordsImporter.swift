import Foundation
import HealthKit
import OSLog
import SwiftData

// MARK: - HealthRecordsImporter

/// Imports clinical records that the Care Recipient has connected to
/// Apple Health via a provider portal (MyChart / Epic, Cerner,
/// athenahealth, …). Each record is a FHIR R4 resource that Apple has
/// already parsed once and hands us back via `HKClinicalRecord.
/// fhirResource`.
///
/// **What we read.** Medications, conditions, allergies, immunizations,
/// lab results, vital signs, procedures, and coverage. The first six
/// are the high-value daily-driver categories; procedures + coverage
/// land in the catch-all view but aren't surfaced elsewhere.
///
/// **Auto-medication seeding.** When we see a `MedicationRequest` or
/// `MedicationStatement` with a recognisable name and dosage, we
/// create a `Medication` row alongside the `HealthRecord` row so the
/// Meds tab fills in without the caregiver having to retype anything
/// the provider already prescribed. The two rows share the HK UUID via
/// `HealthRecord.healthKitUUID` ↔ a derived sentinel on the medication
/// (we don't pollute the Medication schema with HK fields in v1).
///
/// **Dedup.** Re-imports update the existing `HealthRecord` row whose
/// `healthKitUUID` matches the HK record's UUID, so anchor management
/// is not strictly needed; we still keep a `lastImportAt` for the UI
/// banner.
///
/// **Privacy & scope.** All FHIR JSON stays on-device unless the
/// SyncEngine writes the parsed `HealthRecord` row up to the backend
/// (currently it does not — health records remain CloudKit-only in v1).
@Observable
@MainActor
final class HealthRecordsImporter {
    private let store: HKHealthStore?

    var isRunning = false
    var lastImportAt: Date?
    var lastError: String?
    var lastImportedCount = 0

    init() {
        store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static let clinicalIdentifiers: [HKClinicalTypeIdentifier] = [
        .medicationRecord,
        .conditionRecord,
        .allergyRecord,
        .immunizationRecord,
        .labResultRecord,
        .vitalSignRecord,
        .procedureRecord,
        .coverageRecord,
    ]

    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard let store else { return false }
        let readSet: Set<HKObjectType> = Set(
            Self.clinicalIdentifiers.compactMap { HKObjectType.clinicalType(forIdentifier: $0) }
        )
        try await store.requestAuthorization(toShare: [], read: readSet)
        AppLogger.healthKit.info("HK clinical-records auth prompt resolved.")
        return true
    }

    func importAll(into modelContext: ModelContext, circle: Circle) async {
        guard let store else {
            lastError = "Apple Health is not available on this device."
            return
        }
        isRunning = true
        defer { isRunning = false }

        var imported = 0
        for identifier in Self.clinicalIdentifiers {
            do {
                let kind = Self.mapKind(identifier)
                let records = try await readRecords(of: identifier, from: store)
                let count = upsert(
                    records: records,
                    kind: kind,
                    into: modelContext,
                    circle: circle
                )
                imported += count
            } catch {
                AppLogger.healthKit
                    .error(
                        "HK clinical read failed for \(identifier.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
            }
        }

        do {
            try modelContext.save()
            lastError = nil
        } catch {
            lastError = "Couldn't save imported records."
            AppLogger.healthKit
                .error("HK clinical save failed: \(String(describing: error), privacy: .public)")
        }
        lastImportAt = .now
        lastImportedCount = imported
    }

    // MARK: - HealthKit read

    private func readRecords(
        of identifier: HKClinicalTypeIdentifier,
        from store: HKHealthStore
    ) async throws
        -> [HKClinicalRecord]
    {
        guard let type = HKObjectType.clinicalType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let clinical = (samples ?? []).compactMap { $0 as? HKClinicalRecord }
                continuation.resume(returning: clinical)
            }
            store.execute(query)
        }
    }

    // MARK: - Upsert

    @discardableResult
    private func upsert(
        records: [HKClinicalRecord],
        kind: HealthRecord.Kind,
        into modelContext: ModelContext,
        circle: Circle
    )
        -> Int
    {
        var inserted = 0
        let existingByHKUUID: [UUID: HealthRecord] = Dictionary(
            uniqueKeysWithValues: circle.healthRecords
                .filter { $0.kind == kind }
                .map { ($0.healthKitUUID, $0) }
        )

        for record in records {
            let parsed = HealthRecordsParser.parsed(record, kind: kind)
            if let existing = existingByHKUUID[record.uuid] {
                existing.sourceName = parsed.sourceName
                existing.displayTitle = parsed.displayTitle
                existing.displayDetail = parsed.displayDetail
                existing.occurredAt = parsed.occurredAt
                existing.status = parsed.status
                existing.fhirResourceData = parsed.fhirResourceData
                existing.importedAt = .now
            } else {
                let row = HealthRecord(
                    kind: kind,
                    sourceName: parsed.sourceName,
                    displayTitle: parsed.displayTitle,
                    displayDetail: parsed.displayDetail,
                    occurredAt: parsed.occurredAt,
                    status: parsed.status,
                    fhirResourceData: parsed.fhirResourceData,
                    healthKitUUID: record.uuid
                )
                row.circle = circle
                modelContext.insert(row)
                inserted += 1

                if kind == .medication {
                    Self.seedMedicationIfNeeded(
                        parsed: parsed,
                        circle: circle,
                        modelContext: modelContext
                    )
                }
            }
        }
        return inserted
    }

    // MARK: - FHIR parsing (delegated)

    private typealias Parsed = HealthRecordsParser.Parsed

    private static func mapKind(_ identifier: HKClinicalTypeIdentifier) -> HealthRecord.Kind {
        switch identifier {
        case .medicationRecord: .medication
        case .conditionRecord: .condition
        case .allergyRecord: .allergy
        case .immunizationRecord: .immunization
        case .labResultRecord: .labResult
        case .vitalSignRecord: .vitalSign
        case .procedureRecord: .procedure
        case .coverageRecord: .coverage
        default: .condition
        }
    }

    // MARK: - Medication seeding

    private static func seedMedicationIfNeeded(
        parsed: Parsed,
        circle: Circle,
        modelContext: ModelContext
    ) {
        let trimmedTitle = parsed.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let alreadyExists = circle.medications.contains { medication in
            medication.name.caseInsensitiveCompare(trimmedTitle) == .orderedSame
        }
        guard !alreadyExists else { return }

        let (name, dosage) = Self.splitNameAndDosage(parsed.displayTitle)
        let medication = Medication(
            name: name,
            dosage: dosage,
            instructions: parsed.displayDetail.isEmpty ? nil : parsed.displayDetail
        )
        medication.circle = circle
        modelContext.insert(medication)
    }

    private static func splitNameAndDosage(_ raw: String) -> (name: String, dosage: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)(\d+(?:\.\d+)?\s?(mg|mcg|g|ml|iu|units?|%))"#
        if
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(location: 0, length: trimmed.utf16.count)
            ),
            let dosageRange = Range(match.range, in: trimmed)
        {
            let dosage = String(trimmed[dosageRange])
            var name = trimmed
            name.removeSubrange(dosageRange)
            return (name.trimmingCharacters(in: .whitespacesAndNewlines), dosage)
        }
        return (trimmed, "")
    }
}
