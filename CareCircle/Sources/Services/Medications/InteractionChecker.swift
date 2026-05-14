import Foundation

// MARK: - InteractionChecker

/// Ingredient-overlap heuristic used by the pill identifier flow. Compares
/// the active ingredients of a scanned medication against the active
/// medications already in the Circle and emits one row per overlap pair.
///
/// This is NOT a real drug-drug interaction (DDI) database. It only
/// answers "does the bottle you just scanned share an active ingredient
/// with something you're already tracking?" — useful for catching
/// duplicate-therapy mistakes (two different bottles of acetaminophen
/// being given as separate doses), not for predicting pharmacological
/// reactions.
enum InteractionChecker {
    struct Match: Equatable, Sendable, Identifiable {
        let medicationId: UUID
        let medicationName: String
        let ingredient: String

        var id: String {
            "\(medicationId.uuidString)|\(ingredient.lowercased())"
        }
    }

    /// Returns one `Match` per (existing medication, overlapping
    /// ingredient) pair. Ordered by the position of the ingredient in
    /// `result.activeIngredients` so the UI surface stays deterministic.
    static func matches(
        for result: PillIdentificationResult,
        against medications: [Medication]
    )
        -> [Match]
    {
        guard !result.activeIngredients.isEmpty else { return [] }
        let active = medications.filter { $0.status == .active }
        guard !active.isEmpty else { return [] }

        var out: [Match] = []
        for ingredient in result.activeIngredients {
            let needle = ingredient.lowercased()
            for medication in active
                where medication.fdaIngredients.contains(where: { $0.lowercased() == needle })
            {
                out.append(
                    Match(
                        medicationId: medication.id,
                        medicationName: medication.name,
                        ingredient: ingredient
                    )
                )
            }
        }
        return out
    }
}
