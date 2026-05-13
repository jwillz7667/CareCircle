import Foundation
import SwiftData

// MARK: - Medication

@Model
final class Medication {
    var id = UUID()
    var name = ""
    var dosage = ""
    var formRaw: String = MedicationForm.tablet.rawValue
    var statusRaw: String = MedicationStatus.active.rawValue
    var instructions: String?
    var colorHex: String?
    var fdaIngredients: [String] = []
    var startDate: Date?
    var endDate: Date?
    var createdAt = Date.now
    var updatedAt = Date.now
    var scheduleJSON: String?

    var circle: Circle?

    @Relationship(deleteRule: .cascade, inverse: \DoseEvent.medication)
    var doseEvents: [DoseEvent] = []

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .other }
        set { formRaw = newValue.rawValue }
    }

    var status: MedicationStatus {
        get { MedicationStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var schedule: MedicationSchedule {
        get { MedicationSchedule.decode(from: scheduleJSON) ?? MedicationSchedule() }
        set { scheduleJSON = newValue.encodedJSON() }
    }

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        form: MedicationForm = .tablet,
        status: MedicationStatus = .active,
        schedule: MedicationSchedule = MedicationSchedule(),
        instructions: String? = nil,
        colorHex: String? = nil,
        fdaIngredients: [String] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        formRaw = form.rawValue
        statusRaw = status.rawValue
        scheduleJSON = schedule.encodedJSON()
        self.instructions = instructions
        self.colorHex = colorHex
        self.fdaIngredients = fdaIngredients
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}
