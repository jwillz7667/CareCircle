import Foundation

// MARK: - OpenFDALabelResult

/// Normalized subset of an openFDA `/drug/label.json` hit. Only the fields we
/// display in the AddMedication flow.
nonisolated struct OpenFDALabelResult: Equatable, Sendable {
    var brandNames: [String]
    var genericNames: [String]
    var activeIngredients: [String]
}
