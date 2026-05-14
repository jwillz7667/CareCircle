import Foundation
import SwiftData

// MARK: - HealthRecord

/// Read-only clinical fact imported from Apple Health Records — the
/// vehicle Apple uses to pipe data out of provider portals (MyChart /
/// Epic, Cerner, athenahealth, …) into HealthKit. Each row corresponds
/// to one `HKClinicalRecord`; the original FHIR R4 JSON is kept verbatim
/// in `fhirResourceData` for an advanced detail view.
///
/// All fields default so the type is CloudKit-compatible (the shared
/// zone fans these out to the rest of the Circle). Dedup is by the HK
/// `UUID` per circle — re-imports overwrite the existing row in place.
@Model
final class HealthRecord {
    var id = UUID()
    var circle: Circle?

    var kindRaw = HealthRecord.Kind.condition.rawValue
    var sourceName = ""
    var displayTitle = ""
    var displayDetail = ""
    var occurredAt: Date?
    var status = ""
    var fhirResourceData: Data?
    var importedAt = Date.now
    var healthKitUUID = UUID()

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .condition }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: Kind = .condition,
        sourceName: String = "",
        displayTitle: String = "",
        displayDetail: String = "",
        occurredAt: Date? = nil,
        status: String = "",
        fhirResourceData: Data? = nil,
        importedAt: Date = .now,
        healthKitUUID: UUID = UUID()
    ) {
        self.id = id
        kindRaw = kind.rawValue
        self.sourceName = sourceName
        self.displayTitle = displayTitle
        self.displayDetail = displayDetail
        self.occurredAt = occurredAt
        self.status = status
        self.fhirResourceData = fhirResourceData
        self.importedAt = importedAt
        self.healthKitUUID = healthKitUUID
    }

    enum Kind: String, Sendable, CaseIterable {
        case medication
        case condition
        case allergy
        case immunization
        case labResult
        case vitalSign
        case procedure
        case coverage

        var displayName: String {
            switch self {
            case .medication: "Medications"
            case .condition: "Conditions"
            case .allergy: "Allergies"
            case .immunization: "Immunizations"
            case .labResult: "Lab results"
            case .vitalSign: "Vital signs"
            case .procedure: "Procedures"
            case .coverage: "Coverage"
            }
        }

        var systemImageName: String {
            switch self {
            case .medication: "pills.fill"
            case .condition: "stethoscope"
            case .allergy: "exclamationmark.triangle.fill"
            case .immunization: "syringe.fill"
            case .labResult: "testtube.2"
            case .vitalSign: "waveform.path.ecg"
            case .procedure: "scissors"
            case .coverage: "creditcard.fill"
            }
        }
    }
}
