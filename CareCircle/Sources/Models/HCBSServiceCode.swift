import Foundation

// MARK: - HCBSServiceCode

/// Starter set of HCBS (Home and Community-Based Services) service codes
/// most commonly used by Medicaid waiver programs and the dominant fiscal
/// intermediaries (PPL, Acumen, Easterseals). Stored as raw strings on
/// `CareMinuteEntry` so adding new codes is a one-line case insertion
/// without a migration. Source: CMS HCBS Taxonomy v3.2 and the PPL
/// service catalog overlap, May 2026.
///
/// New codes should be added with a one-line case. The catalog is
/// state-specific — what's billable in NY's CDPAP differs from Ohio's.
enum HCBSServiceCode: String, CaseIterable, Codable, Sendable, Identifiable {
    case personalCare = "T1019"
    case companion = "S5125"
    case mealPreparation = "S5170"
    case homemaker = "S5130"
    case respiteCare = "T1005"
    case nonEmergencyTransport = "T2003"
    case medicalEscort = "T2007"
    case adultDayCare = "S5100"
    case skilledNursing = "T1000"
    case other = "OTHER"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .personalCare: "Personal care"
        case .companion: "Companion"
        case .mealPreparation: "Meal preparation"
        case .homemaker: "Homemaker"
        case .respiteCare: "Respite care"
        case .nonEmergencyTransport: "Non-emergency transport"
        case .medicalEscort: "Medical escort"
        case .adultDayCare: "Adult day care"
        case .skilledNursing: "Skilled nursing"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .personalCare: "figure.dress.line.vertical.figure"
        case .companion: "person.2.fill"
        case .mealPreparation: "fork.knife"
        case .homemaker: "house.fill"
        case .respiteCare: "moon.zzz.fill"
        case .nonEmergencyTransport: "car.fill"
        case .medicalEscort: "stethoscope"
        case .adultDayCare: "sun.max.fill"
        case .skilledNursing: "cross.case.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    static func from(raw: String) -> HCBSServiceCode {
        HCBSServiceCode(rawValue: raw) ?? .other
    }
}
