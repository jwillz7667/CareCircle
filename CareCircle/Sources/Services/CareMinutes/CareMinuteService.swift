import Foundation

// MARK: - CareMinuteService

/// Pure helpers for the care-minutes feature: week boundaries, rollups,
/// PDF export filename. Stateless on purpose so views and the renderer
/// can share the same math without an injected dependency.
enum CareMinuteService {
    /// Locale-aware [start, end) for the calendar week containing `date`.
    /// Uses `Calendar.current` so the week start respects the user's
    /// region (Sunday in en-US, Monday in en-GB, etc.).
    static func weekRange(containing date: Date) -> Range<Date> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: startOfDay) {
            return weekInterval.start ..< weekInterval.end
        }
        let fallback = calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? startOfDay
        return startOfDay ..< fallback
    }

    static func entries(in range: Range<Date>, from all: [CareMinuteEntry]) -> [CareMinuteEntry] {
        all.filter { entry in
            entry.startedAt >= range.lowerBound && entry.startedAt < range.upperBound
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    static func totalMinutes(in entries: [CareMinuteEntry]) -> Int {
        entries.reduce(0) { $0 + $1.durationMinutes }
    }

    static func totalHoursFormatted(in entries: [CareMinuteEntry]) -> String {
        let totalMinutes = totalMinutes(in: entries)
        let hours = Double(totalMinutes) / 60.0
        return String(format: "%.2f h", hours)
    }

    static func groupedByDay(_ entries: [CareMinuteEntry]) -> [(day: Date, entries: [CareMinuteEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt) }
        return grouped
            .map { (day: $0.key, entries: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.day < $1.day }
    }

    static func groupedByServiceCode(_ entries: [CareMinuteEntry]) -> [(
        code: HCBSServiceCode,
        entries: [CareMinuteEntry]
    )] {
        let grouped = Dictionary(grouping: entries) { $0.serviceCode }
        return grouped
            .map { (code: $0.key, entries: $0.value) }
            .sorted { $0.code.displayName < $1.code.displayName }
    }

    static func exportFilename(for range: Range<Date>, circleName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let safeCircle = circleName
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let weekStart = formatter.string(from: range.lowerBound)
        return "CareMinutes_\(safeCircle.isEmpty ? "Circle" : safeCircle)_\(weekStart).pdf"
    }
}
