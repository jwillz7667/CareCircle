import Foundation

// MARK: - DocumentType

/// Taxonomy of document categories supported in v1. Mirrors the spec's
/// document_type enum so backend portability is preserved later.
enum DocumentType: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case insuranceCard = "insurance_card"
    case advanceDirective = "advance_directive"
    case dnr
    case medList = "med_list"
    case visitSummary = "visit_summary"
    case eob
    case labResult = "lab_result"
    case identification
    case other

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .insuranceCard: "Insurance card"
        case .advanceDirective: "Advance directive"
        case .dnr: "DNR / POLST"
        case .medList: "Medication list"
        case .visitSummary: "Visit summary"
        case .eob: "Explanation of benefits"
        case .labResult: "Lab result"
        case .identification: "Identification"
        case .other: "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .insuranceCard: "creditcard.fill"
        case .advanceDirective: "doc.text.fill"
        case .dnr: "exclamationmark.shield.fill"
        case .medList: "list.bullet.rectangle.fill"
        case .visitSummary: "stethoscope"
        case .eob: "doc.plaintext.fill"
        case .labResult: "testtube.2"
        case .identification: "person.text.rectangle.fill"
        case .other: "doc.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .insuranceCard: 0
        case .identification: 1
        case .advanceDirective: 2
        case .dnr: 3
        case .medList: 4
        case .visitSummary: 5
        case .labResult: 6
        case .eob: 7
        case .other: 8
        }
    }
}
