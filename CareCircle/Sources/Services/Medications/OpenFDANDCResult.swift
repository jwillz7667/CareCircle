import Foundation

// MARK: - OpenFDANDCResult

/// Normalized subset of an openFDA `/drug/ndc.json` hit. Carries the
/// product-level metadata we surface in the pill identifier flow.
///
/// Distinct from `OpenFDALabelResult` because the NDC product endpoint
/// includes route + dosage form + the matched `product_ndc` itself,
/// which the label endpoint does not.
nonisolated struct OpenFDANDCResult: Equatable, Sendable {
    var productNDC: String
    var brandNames: [String]
    var genericNames: [String]
    var activeIngredients: [String]
    var routes: [String]
    var dosageForms: [String]
}
