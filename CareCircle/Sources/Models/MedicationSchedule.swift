import Foundation

// MARK: - MedicationSchedule

nonisolated struct MedicationSchedule: Codable, Sendable, Equatable {
    enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily
        case weekly
        case asNeeded

        var displayName: String {
            switch self {
            case .daily: "Every day"
            case .weekly: "Specific days"
            case .asNeeded: "As needed"
            }
        }
    }

    /// Hour/minute pairs interpreted in the user's current calendar.
    nonisolated struct TimeOfDay: Codable, Sendable, Equatable, Hashable, Identifiable {
        var id = UUID()
        var hour: Int
        var minute: Int

        init(id: UUID = UUID(), hour: Int, minute: Int) {
            self.id = id
            self.hour = max(0, min(23, hour))
            self.minute = max(0, min(59, minute))
        }

        func formatted(in calendar: Calendar = .current) -> String {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            guard let date = calendar.date(from: components) else {
                return String(format: "%02d:%02d", hour, minute)
            }
            return date.formatted(date: .omitted, time: .shortened)
        }
    }

    var frequency: Frequency
    var timesOfDay: [TimeOfDay]
    /// 1 = Sunday … 7 = Saturday. Empty means every day.
    var daysOfWeek: Set<Int>

    init(
        frequency: Frequency = .daily,
        timesOfDay: [TimeOfDay] = [],
        daysOfWeek: Set<Int> = []
    ) {
        self.frequency = frequency
        self.timesOfDay = timesOfDay
        self.daysOfWeek = daysOfWeek
    }

    static func decode(from json: String?) -> MedicationSchedule? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MedicationSchedule.self, from: data)
    }

    func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var describesAnyTime: Bool {
        frequency == .asNeeded || timesOfDay.isEmpty
    }

    func upcomingOccurrences(
        after start: Date,
        limit: Int,
        calendar: Calendar = .current
    )
        -> [Date]
    {
        guard !timesOfDay.isEmpty, frequency != .asNeeded else { return [] }

        var results: [Date] = []
        var day = calendar.startOfDay(for: start)
        let cap = 21
        var safety = 0
        while results.count < limit, safety < cap {
            defer {
                safety += 1
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            let weekday = calendar.component(.weekday, from: day)
            if frequency == .weekly, !daysOfWeek.isEmpty, !daysOfWeek.contains(weekday) {
                continue
            }
            for time in timesOfDay.sorted(by: { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) {
                guard let occurrence = calendar.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: day
                ) else { continue }
                if occurrence > start {
                    results.append(occurrence)
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    func summary(calendar: Calendar = .current) -> String {
        switch frequency {
        case .asNeeded:
            return "As needed"
        case .daily:
            let times = timeListSummary(calendar: calendar)
            return times.isEmpty ? "Daily" : "Daily at \(times)"
        case .weekly:
            let days = weekdaySummary(calendar: calendar)
            let times = timeListSummary(calendar: calendar)
            switch (days.isEmpty, times.isEmpty) {
            case (false, false): return "\(days) at \(times)"
            case (false, true): return days
            case (true, false): return "Weekly at \(times)"
            case (true, true): return "Weekly"
            }
        }
    }

    private func timeListSummary(calendar: Calendar) -> String {
        timesOfDay
            .sorted(by: { ($0.hour, $0.minute) < ($1.hour, $1.minute) })
            .map { $0.formatted(in: calendar) }
            .joined(separator: ", ")
    }

    private func weekdaySummary(calendar: Calendar) -> String {
        guard !daysOfWeek.isEmpty else { return "Every day" }
        let symbols = calendar.shortWeekdaySymbols
        return daysOfWeek
            .sorted()
            .compactMap { index in
                let idx = index - 1
                return idx >= 0 && idx < symbols.count ? symbols[idx] : nil
            }
            .joined(separator: ", ")
    }
}
