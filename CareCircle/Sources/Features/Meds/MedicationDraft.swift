import Foundation

// MARK: - MedicationDraft

/// Mutable scratchpad backing `AddMedicationView` / `EditMedicationView`. Keeps
/// validation logic out of the views and lets the same form support both create
/// and edit paths.
struct MedicationDraft: Equatable {
    var name: String
    var dosage: String
    var form: MedicationForm
    var status: MedicationStatus
    var schedule: MedicationSchedule
    var instructions: String
    var colorHex: String?
    var startDate: Date?
    var endDate: Date?
    var fdaIngredients: [String]

    init(
        name: String = "",
        dosage: String = "",
        form: MedicationForm = .tablet,
        status: MedicationStatus = .active,
        schedule: MedicationSchedule = MedicationSchedule(),
        instructions: String = "",
        colorHex: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        fdaIngredients: [String] = []
    ) {
        self.name = name
        self.dosage = dosage
        self.form = form
        self.status = status
        self.schedule = schedule
        self.instructions = instructions
        self.colorHex = colorHex
        self.startDate = startDate
        self.endDate = endDate
        self.fdaIngredients = fdaIngredients
    }

    init(medication: Medication) {
        name = medication.name
        dosage = medication.dosage
        form = medication.form
        status = medication.status
        schedule = medication.schedule
        instructions = medication.instructions ?? ""
        colorHex = medication.colorHex
        startDate = medication.startDate
        endDate = medication.endDate
        fdaIngredients = medication.fdaIngredients
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDosage: String {
        dosage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        guard !trimmedName.isEmpty, !trimmedDosage.isEmpty else { return false }
        switch status {
        case .discontinued:
            return true
        case .asNeeded:
            return true
        case .active:
            switch schedule.frequency {
            case .asNeeded:
                return true
            case .daily, .weekly:
                return !schedule.timesOfDay.isEmpty
            }
        }
    }

    func apply(to medication: Medication, now: Date = .now) {
        medication.name = trimmedName
        medication.dosage = trimmedDosage
        medication.form = form
        medication.status = status
        medication.schedule = schedule
        medication.instructions = trimmedInstructions.isEmpty ? nil : trimmedInstructions
        medication.colorHex = colorHex
        medication.startDate = startDate
        medication.endDate = endDate
        medication.fdaIngredients = fdaIngredients
        medication.updatedAt = now
    }
}
