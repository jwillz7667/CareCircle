import Foundation

// MARK: - MissedDoseRiskPattern

/// Looks at the last 14 days of `.missed` and `.skipped` dose events
/// for each medication, groups them by scheduled hour-of-day, and
/// emits a `.warning` insight when any single time-of-day bucket
/// accumulates three or more misses.
///
/// We group by hour-of-day rather than day-of-week because the
/// pattern we care about — "the morning dose keeps getting missed" —
/// shows up clearly in the hour bucket but is too sparse weekly. The
/// threshold is intentionally low: three missed morning doses in two
/// weeks is enough signal to ask the user to consider an alternative.
struct MissedDoseRiskPattern: InsightPattern {
    let kind: InsightKind = .missedDoseRisk
    let windowDays: Int
    let threshold: Int

    init(windowDays: Int = 14, threshold: Int = 3) {
        self.windowDays = windowDays
        self.threshold = threshold
    }

    func derive(from circle: Circle) -> [DerivedInsight] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: .now) ?? .distantPast

        return circle.medications.compactMap { medication in
            guard medication.status == .active else { return nil }
            let buckets = bucketCounts(for: medication, since: windowStart, calendar: calendar)
            guard let worst = buckets.max(by: { $0.value < $1.value }),
                  worst.value >= threshold else { return nil }
            return buildInsight(
                medication: medication,
                hour: worst.key,
                count: worst.value,
                calendar: calendar
            )
        }
    }

    // MARK: Helpers

    private func bucketCounts(
        for medication: Medication,
        since: Date,
        calendar: Calendar
    )
        -> [Int: Int]
    {
        var counts: [Int: Int] = [:]
        for event in medication.doseEvents where event.scheduledAt >= since {
            guard event.status == .missed || event.status == .skipped else { continue }
            let hour = calendar.component(.hour, from: event.scheduledAt)
            counts[hour, default: 0] += 1
        }
        return counts
    }

    private func buildInsight(
        medication: Medication,
        hour: Int,
        count: Int,
        calendar _: Calendar
    )
        -> DerivedInsight
    {
        let timeOfDay = timeOfDayLabel(for: hour)
        let title = "\(medication.name) missed \(count) times in \(windowDays) days"
        let body = "The \(timeOfDay) dose was missed or skipped \(count) times in the last \(windowDays) days. Consider setting a louder alert, picking a different time, or asking another caregiver to cover that slot."
        return DerivedInsight(
            kind: kind,
            severity: .warning,
            subjectKind: .medication,
            subjectId: medication.id,
            title: title,
            body: body,
            payloadJSON: nil
        )
    }

    private func timeOfDayLabel(for hour: Int) -> String {
        switch hour {
        case 5 ..< 12: "morning"
        case 12 ..< 17: "afternoon"
        case 17 ..< 21: "evening"
        default: "overnight"
        }
    }
}
