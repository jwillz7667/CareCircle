import Foundation

// MARK: - FHIRReader

/// Best-effort accessors for the handful of FHIR R4 fields we actually
/// surface in the UI. Apple's HealthKit hands us already-validated FHIR
/// resources, so we don't need a full schema-validating client — we
/// just dig out the human-readable bits.
///
/// Every helper is forgiving: malformed or absent fields return `nil`
/// (or an empty result) instead of throwing, because the worst-case UX
/// is a record showing a slightly less specific title, not a crash.
enum FHIRReader {
    // MARK: - CodeableConcept

    /// FHIR `CodeableConcept` resolves to `text` if present, otherwise
    /// the first `coding[].display`, otherwise the first `coding[].code`.
    static func codeableConceptText(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let text = dict["text"] as? String, !text.isEmpty {
            return text
        }
        if let codings = dict["coding"] as? [[String: Any]] {
            for coding in codings {
                if let display = coding["display"] as? String, !display.isEmpty {
                    return display
                }
            }
            for coding in codings {
                if let code = coding["code"] as? String, !code.isEmpty {
                    return code
                }
            }
        }
        return nil
    }

    // MARK: - DateTime

    static func dateTime(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = isoFractional.date(from: raw) { return date }
        if let date = isoPlain.date(from: raw) { return date }
        if let date = dateOnly.date(from: raw) { return date }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Medication

    static func medicationTitle(from json: [String: Any]) -> String? {
        if let text = codeableConceptText(json["medicationCodeableConcept"]) {
            return text
        }
        if let medRef = json["medicationReference"] as? [String: Any],
           let display = medRef["display"] as? String, !display.isEmpty
        {
            return display
        }
        if let contained = json["contained"] as? [[String: Any]],
           let first = contained.first,
           let text = codeableConceptText(first["code"])
        {
            return text
        }
        return nil
    }

    static func medicationDetail(from json: [String: Any]) -> String? {
        guard let dosages = json["dosageInstruction"] as? [[String: Any]],
              let first = dosages.first else { return nil }
        if let text = first["text"] as? String, !text.isEmpty {
            return text
        }
        if let route = codeableConceptText(first["route"]) {
            return route
        }
        return nil
    }

    // MARK: - Observation

    /// FHIR `Observation.value[x]`. Tries `valueQuantity` (with unit),
    /// then `valueString`, then `valueCodeableConcept`.
    static func observationValue(from json: [String: Any]) -> String? {
        if let qty = json["valueQuantity"] as? [String: Any] {
            let value = qty["value"]
            let unit = (qty["unit"] as? String) ?? (qty["code"] as? String) ?? ""
            if let value {
                return "\(value) \(unit)".trimmingCharacters(in: .whitespaces)
            }
        }
        if let valueString = json["valueString"] as? String, !valueString.isEmpty {
            return valueString
        }
        if let text = codeableConceptText(json["valueCodeableConcept"]) {
            return text
        }
        return nil
    }

    // MARK: - Severity (Condition.severity)

    static func severityText(_ json: [String: Any]) -> String? {
        if let severity = codeableConceptText(json["severity"]) {
            return "Severity: \(severity)"
        }
        return nil
    }
}
