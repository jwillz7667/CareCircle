import Foundation

// MARK: - VitalFormatting

/// Locale-aware helpers shared by every vitals view so a number
/// rendered in the row, the detail screen, and the chart axis always
/// agrees on rounding and unit punctuation.
enum VitalFormatting {
    /// Returns a numeric string for the vital's primary value. Steps
    /// and falls are integers; everything else gets one decimal except
    /// glucose, blood pressure, and respiratory rate which the medical
    /// convention is to display whole-numbered.
    static func formattedValue(_ vital: Vital) -> String {
        if let text = vital.valueText, !text.isEmpty {
            return text
        }
        guard let value = vital.valueNumeric else { return "—" }
        return formattedValue(value, kind: vital.kind)
    }

    static func formattedValue(_ value: Double, kind: VitalKind) -> String {
        let formatter = Self.formatter(for: kind)
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "120 mmHg" / "98.6 °F" / "12,407 steps" with proper non-breaking
    /// space between value and unit so the line never wraps in
    /// awkward places at small Dynamic Type sizes.
    static func formattedValueWithUnit(_ vital: Vital) -> String {
        let value = formattedValue(vital)
        let unit = vital.unit
        guard !unit.isEmpty else { return value }
        return "\(value)\u{00A0}\(unit)"
    }

    private static func formatter(for kind: VitalKind) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        switch kind {
        case .stepCount, .falls:
            formatter.maximumFractionDigits = 0
        case .bloodGlucose,
             .bloodPressureSystolic,
             .bloodPressureDiastolic,
             .respiratoryRate,
             .heartRate,
             .restingHeartRate:
            formatter.maximumFractionDigits = 0
        case .bodyWeight, .bodyTemperature, .sleepHours, .walkingSteadiness, .oxygenSaturation:
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
        }
        return formatter
    }

    static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeRecordedAt(_ date: Date, reference: Date = .now) -> String {
        relativeTimeFormatter.localizedString(for: date, relativeTo: reference)
    }

    static let absoluteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func absoluteRecordedAt(_ date: Date) -> String {
        absoluteTimeFormatter.string(from: date)
    }
}
