import Foundation

// MARK: - PillIdentificationResult

/// Normalized result of an openFDA NDC lookup, plus the raw payload the
/// scanner returned so the UI can surface "we scanned X" context.
///
/// Reuses `OpenFDALabelResult` fields for brand/generic/active-ingredient
/// strings so the existing display logic in `MedicationFDASection` and the
/// `MedicationDraft` builder can be lifted into the result screen without
/// duplicate models.
nonisolated struct PillIdentificationResult: Equatable, Sendable {
    /// The raw barcode payload the scanner emitted (typically a 12-digit
    /// UPC-A). Surfaces in the UI as "Scanned XXXXXXXXXXXX" so the user
    /// can sanity-check against the bottle.
    var scannedPayload: String

    /// The NDC format that produced the hit (e.g. "12345-6789"). Useful
    /// for the result row and for re-querying openFDA from the
    /// AddMedication flow if the user accepts the suggestion.
    var matchedNDC: String

    /// Marketed brand names from `openfda.brand_name`.
    var brandNames: [String]

    /// Generic names from `openfda.generic_name`.
    var genericNames: [String]

    /// Active ingredients, deduped + title-cased. Drives the interaction
    /// overlap heuristic and pre-fills `Medication.fdaIngredients` when
    /// the user adopts the scanned medication.
    var activeIngredients: [String]

    /// Administration route (e.g. "ORAL"). openFDA surfaces these as
    /// upper-case strings; we keep them as-is and let the view title-case
    /// for display.
    var routes: [String]

    /// Dosage form (e.g. "TABLET, FILM COATED"). Used to map into
    /// `MedicationForm` heuristically — the mapping is best-effort and
    /// falls back to `.other` when ambiguous.
    var dosageForms: [String]

    /// The best display name to show as a heading. Prefers the first
    /// brand name, falls back to the first generic name, finally the
    /// matched NDC.
    var displayName: String {
        if let brand = brandNames.first { return brand }
        if let generic = genericNames.first { return generic }
        return matchedNDC
    }
}
