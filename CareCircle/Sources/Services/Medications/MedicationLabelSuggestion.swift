import Foundation

// MARK: - MedicationLabelSuggestion

/// Result of running the label parser over OCR text from the camera scanner.
nonisolated struct MedicationLabelSuggestion: Equatable, Sendable {
    var name: String
    var dosage: String?
    var form: MedicationForm?

    static let empty = MedicationLabelSuggestion(name: "", dosage: nil, form: nil)

    var isUseful: Bool {
        !name.isEmpty || (dosage?.isEmpty == false) || form != nil
    }
}
