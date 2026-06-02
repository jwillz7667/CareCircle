import Foundation
import HealthKit

// MARK: - HealthRecordsParser

/// Dispatches an `HKClinicalRecord` to the kind-specific FHIR parser
/// and returns the normalised fields we surface in CareCircle's UI.
/// Keeping this out of `HealthRecordsImporter` keeps the importer
/// focused on I/O + persistence and lets each parser stay small.
enum HealthRecordsParser {
    struct Parsed {
        let sourceName: String
        let displayTitle: String
        let displayDetail: String
        let occurredAt: Date?
        let status: String
        let fhirResourceData: Data?
    }

    static func parsed(_ record: HKClinicalRecord, kind: HealthRecord.Kind) -> Parsed {
        let fhirData = record.fhirResource?.data
        let sourceName = record.sourceRevision.source.name

        guard
            let data = fhirData,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            return Parsed(
                sourceName: sourceName,
                displayTitle: record.displayName,
                displayDetail: "",
                occurredAt: record.endDate,
                status: "",
                fhirResourceData: fhirData
            )
        }

        let fields = dispatch(kind: kind, json: json, record: record)
        return Parsed(
            sourceName: sourceName,
            displayTitle: fields.title,
            displayDetail: fields.detail,
            occurredAt: fields.occurredAt,
            status: fields.status,
            fhirResourceData: fhirData
        )
    }

    // MARK: - Dispatch

    private struct Fields {
        let title: String
        let detail: String
        let occurredAt: Date?
        let status: String
    }

    private static func dispatch(
        kind: HealthRecord.Kind,
        json: [String: Any],
        record: HKClinicalRecord
    )
        -> Fields
    {
        switch kind {
        case .medication: medication(json: json, record: record)
        case .condition: condition(json: json, record: record)
        case .allergy: allergy(json: json, record: record)
        case .immunization: immunization(json: json, record: record)
        case .labResult: labResult(json: json, record: record)
        case .vitalSign: vitalSign(json: json, record: record)
        case .procedure: procedure(json: json, record: record)
        case .coverage: coverage(json: json, record: record)
        }
    }

    // MARK: - Per-kind

    private static func medication(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.medicationTitle(from: json) ?? record.displayName,
            detail: FHIRReader.medicationDetail(from: json) ?? "",
            occurredAt: FHIRReader.dateTime(from: json["authoredOn"] as? String)
                ?? FHIRReader.dateTime(from: json["effectiveDateTime"] as? String)
                ?? record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }

    private static func condition(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["code"]) ?? record.displayName,
            detail: FHIRReader.severityText(json) ?? "",
            occurredAt: FHIRReader.dateTime(from: json["onsetDateTime"] as? String)
                ?? FHIRReader.dateTime(from: json["recordedDate"] as? String)
                ?? record.endDate,
            status: FHIRReader.codeableConceptText(json["clinicalStatus"]) ?? ""
        )
    }

    private static func allergy(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["code"]) ?? record.displayName,
            detail: (json["criticality"] as? String).map { "Criticality: \($0)" } ?? "",
            occurredAt: FHIRReader.dateTime(from: json["recordedDate"] as? String)
                ?? record.endDate,
            status: FHIRReader.codeableConceptText(json["clinicalStatus"]) ?? ""
        )
    }

    private static func immunization(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["vaccineCode"]) ?? record.displayName,
            detail: (json["lotNumber"] as? String).map { "Lot: \($0)" } ?? "",
            occurredAt: FHIRReader.dateTime(from: json["occurrenceDateTime"] as? String)
                ?? record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }

    private static func labResult(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["code"]) ?? record.displayName,
            detail: FHIRReader.observationValue(from: json) ?? "",
            occurredAt: FHIRReader.dateTime(from: json["effectiveDateTime"] as? String)
                ?? record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }

    private static func vitalSign(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["code"]) ?? record.displayName,
            detail: FHIRReader.observationValue(from: json) ?? "",
            occurredAt: FHIRReader.dateTime(from: json["effectiveDateTime"] as? String)
                ?? record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }

    private static func procedure(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: FHIRReader.codeableConceptText(json["code"]) ?? record.displayName,
            detail: "",
            occurredAt: FHIRReader.dateTime(from: json["performedDateTime"] as? String)
                ?? record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }

    private static func coverage(json: [String: Any], record: HKClinicalRecord) -> Fields {
        Fields(
            title: (json["type"] as? [String: Any])
                .flatMap { FHIRReader.codeableConceptText($0) } ?? record.displayName,
            detail: (json["subscriberId"] as? String).map { "Subscriber ID: \($0)" } ?? "",
            occurredAt: record.endDate,
            status: (json["status"] as? String) ?? ""
        )
    }
}
