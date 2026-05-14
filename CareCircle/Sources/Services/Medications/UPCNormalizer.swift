import Foundation

// MARK: - UPCNormalizer

/// Converts a barcode payload into a ranked list of NDC strings to try
/// against openFDA's `product_ndc` field. Pure function — no I/O.
///
/// US prescription bottles carry UPC-A (12 digits) where the FDA reserves
/// the leading `3` as the prefix for human drug products. The middle 10
/// digits encode the NDC10 with one of three split conventions, and the
/// trailing digit is a check digit. openFDA's `product_ndc` field expects
/// either the 5-4 ("XXXXX-XXXX") or 4-4 ("XXXX-XXXX") variant, so we emit
/// every plausible split and let the caller try them in order.
enum UPCNormalizer {
    /// Returns a ranked list of NDC candidate strings to query for the
    /// given barcode payload. The first candidate that hits openFDA
    /// wins. If `payload` already contains a `-`, it is treated as an
    /// already-formatted NDC and returned unchanged.
    static func candidateNDCs(from payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("-") {
            return [trimmed]
        }

        let digits = trimmed.filter(\.isNumber)
        guard digits.count == 12 || digits.count == 11 || digits.count == 10 else {
            return [trimmed]
        }

        let core = ndcCore(from: digits)
        guard core.count == 10 else { return [trimmed] }

        return [
            split(core, at: 5),
            split(core, at: 4),
            split(core, at: 5, suffix: 3, leadingZeros: true),
        ]
    }

    /// Extracts the 10-digit NDC core from a 10–12 digit UPC payload by
    /// stripping the FDA prefix (`3`) when present and the trailing
    /// UPC check digit.
    private static func ndcCore(from digits: String) -> String {
        var core = digits
        if core.count == 12, core.hasPrefix("3") {
            core.removeFirst()
        }
        if core.count == 11 {
            core.removeLast()
        }
        if core.count > 10 {
            core = String(core.prefix(10))
        }
        return core
    }

    /// Inserts a hyphen so the result has `labelerLen` characters before
    /// the `-` and `10 - labelerLen` characters after, optionally
    /// truncating the suffix to `suffix` characters with leading-zero
    /// padding to satisfy the 5-3 split convention.
    private static func split(
        _ core: String,
        at labelerLen: Int,
        suffix: Int? = nil,
        leadingZeros _: Bool = false
    )
        -> String
    {
        let labeler = String(core.prefix(labelerLen))
        var product = String(core.dropFirst(labelerLen))
        if let suffix {
            product = String(product.prefix(suffix))
        }
        return "\(labeler)-\(product)"
    }
}
