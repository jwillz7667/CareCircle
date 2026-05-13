import Foundation

// MARK: - MedicationLabelParser

/// Heuristic parser that turns raw OCR lines from a prescription label into a
/// best-guess `MedicationLabelSuggestion`. Intentionally conservative — the
/// user always confirms in `AddMedicationView` before any data is saved.
nonisolated struct MedicationLabelParser: Sendable {
    private static let doseRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(mg|mcg|ml|g|iu|%)"#,
        options: [.caseInsensitive]
    )

    private static let formKeywords: [(keyword: String, form: MedicationForm)] = [
        ("tablet", .tablet),
        ("tab ", .tablet),
        ("capsule", .capsule),
        ("cap ", .capsule),
        ("liquid", .liquid),
        ("syrup", .liquid),
        ("solution", .liquid),
        ("suspension", .liquid),
        ("injection", .injection),
        ("syringe", .injection),
        ("patch", .patch),
        ("inhaler", .inhaler),
        ("puff", .inhaler),
        ("cream", .cream),
        ("ointment", .cream),
        ("drops", .drops),
        ("gtt", .drops),
    ]

    private static let stopwords: Set<String> = [
        "rx", "ndc", "lot", "exp", "qty", "refills", "pharmacy", "patient",
        "directions", "warning", "warnings", "use", "use:", "see", "side",
        "store", "keep", "tablets", "capsules", "doctor", "physician", "take",
        "by", "mouth", "every", "daily", "hours", "hour", "dose", "doses",
        "active", "inactive", "ingredients",
    ]

    func parse(lines: [String]) -> MedicationLabelSuggestion {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return .empty }

        let dosage = extractDosage(from: cleaned)
        let form = extractForm(from: cleaned)
        let name = extractName(from: cleaned, dosage: dosage)
        return MedicationLabelSuggestion(name: name, dosage: dosage, form: form)
    }

    private func extractDosage(from lines: [String]) -> String? {
        guard let regex = Self.doseRegex else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex ..< line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let amountRange = Range(match.range(at: 1), in: line),
               let unitRange = Range(match.range(at: 2), in: line)
            {
                let amount = String(line[amountRange])
                let unit = String(line[unitRange]).lowercased()
                return "\(amount) \(unit)"
            }
        }
        return nil
    }

    private func extractForm(from lines: [String]) -> MedicationForm? {
        let combined = lines.joined(separator: " ").lowercased()
        for entry in Self.formKeywords where combined.contains(entry.keyword) {
            return entry.form
        }
        return nil
    }

    private func extractName(from lines: [String], dosage: String?) -> String {
        for raw in lines {
            let candidate = nameCandidate(from: raw, dosage: dosage)
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }

    private func nameCandidate(from line: String, dosage: String?) -> String {
        var working = line
        if let dosage {
            working = working.replacingOccurrences(of: dosage, with: "", options: .caseInsensitive)
        }
        for entry in Self.formKeywords {
            working = working.replacingOccurrences(
                of: entry.keyword,
                with: "",
                options: .caseInsensitive
            )
        }
        let tokens = working
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let alphaTokens = tokens.filter { token in
            let lower = token.lowercased()
            guard !Self.stopwords.contains(lower) else { return false }
            return token.allSatisfy { $0.isLetter || $0.isNumber } && token.contains(where: \.isLetter)
        }

        let longTokens = alphaTokens.filter { $0.count >= 3 }
        guard let first = longTokens.first else { return "" }
        let cleaned = first.lowercased()
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}
