import Foundation

// MARK: - MedicationStatus

enum MedicationStatus: String, Codable, CaseIterable, Sendable {
    case active
    case asNeeded
    case discontinued

    var displayName: String {
        switch self {
        case .active: "Active"
        case .asNeeded: "As needed"
        case .discontinued: "Discontinued"
        }
    }

    var sortOrder: Int {
        switch self {
        case .active: 0
        case .asNeeded: 1
        case .discontinued: 2
        }
    }
}

// MARK: - MedicationForm

enum MedicationForm: String, Codable, CaseIterable, Sendable {
    case tablet
    case capsule
    case liquid
    case injection
    case patch
    case inhaler
    case cream
    case drops
    case other

    var displayName: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .liquid: "Liquid"
        case .injection: "Injection"
        case .patch: "Patch"
        case .inhaler: "Inhaler"
        case .cream: "Cream"
        case .drops: "Drops"
        case .other: "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .tablet, .capsule: "pills.fill"
        case .liquid, .drops: "drop.fill"
        case .injection: "syringe.fill"
        case .patch: "rectangle.fill"
        case .inhaler: "wind"
        case .cream: "tube.fill"
        case .other: "cross.case.fill"
        }
    }
}

// MARK: - DoseStatus

enum DoseStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case taken
    case skipped
    case missed
    case late

    var displayName: String {
        switch self {
        case .scheduled: "Scheduled"
        case .taken: "Taken"
        case .skipped: "Skipped"
        case .missed: "Missed"
        case .late: "Late"
        }
    }
}
