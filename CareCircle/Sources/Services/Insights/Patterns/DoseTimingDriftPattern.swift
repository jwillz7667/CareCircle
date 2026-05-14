import Foundation

// MARK: - DoseTimingDriftPattern

/// Looks at the last 14 days of `.taken` and `.late` dose events for
/// each medication. If the median offset between scheduled and actual
/// time exceeds ±30 minutes with a sample size of at least 7 events,
/// emits a `doseTimingDrift` insight suggesting the user move the
/// reminder time.
///
/// We use the median (not mean) so a single very-late dose doesn't
/// pull the recommendation. 14 days is long enough to absorb a
/// disrupted week but short enough that a recent change in routine
/// surfaces quickly.
struct DoseTimingDriftPattern: InsightPattern {
    let kind: InsightKind = .doseTimingDrift
    let windowDays: Int
    let minSamples: Int
    let driftThresholdSeconds: TimeInterval

    init(
        windowDays: Int = 14,
        minSamples: Int = 7,
        driftThresholdSeconds: TimeInterval = 30 * 60
    ) {
        self.windowDays = windowDays
        self.minSamples = minSamples
        self.driftThresholdSeconds = driftThresholdSeconds
    }

    func derive(from circle: Circle) -> [DerivedInsight] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: .now) ?? .distantPast

        return circle.medications.compactMap { medication in
            guard medication.status == .active else { return nil }
            let offsets = sampleOffsets(for: medication, since: windowStart)
            guard offsets.count >= minSamples else { return nil }
            let median = median(of: offsets)
            guard abs(median) > driftThresholdSeconds else { return nil }
            return buildInsight(medication: medication, medianSeconds: median)
        }
    }

    // MARK: Helpers

    private func sampleOffsets(for medication: Medication, since: Date) -> [TimeInterval] {
        medication.doseEvents
            .filter { $0.scheduledAt >= since }
            .filter { $0.status == .taken || $0.status == .late }
            .compactMap { event in
                guard let takenAt = event.takenAt else { return nil }
                return takenAt.timeIntervalSince(event.scheduledAt)
            }
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let count = sorted.count
        if count.isMultiple(of: 2) {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

    private func buildInsight(medication: Medication, medianSeconds: TimeInterval) -> DerivedInsight {
        let minutes = Int(medianSeconds.rounded() / 60)
        let absMinutes = abs(minutes)
        let directionTitle = minutes > 0 ? "late" : "early"
        let title = "\(medication.name) typically taken \(absMinutes) min \(directionTitle)"
        let body = if minutes > 0 {
            "Over the last \(windowDays) days, doses have been taken \(absMinutes) minutes after the scheduled time. Consider moving the reminder forward."
        } else {
            "Over the last \(windowDays) days, doses have been taken \(absMinutes) minutes before the scheduled time. Consider moving the reminder back."
        }

        let payload = DriftPayload(suggestedShiftMinutes: minutes)
        return DerivedInsight(
            kind: kind,
            severity: .suggestion,
            subjectKind: .medication,
            subjectId: medication.id,
            title: title,
            body: body,
            payloadJSON: payload.encodedJSON()
        )
    }
}

// MARK: - DriftPayload

/// Encodes the recommended reminder-time shift. The medication detail
/// view reads `suggestedShiftMinutes` and pre-fills the time picker.
nonisolated struct DriftPayload: Codable, Sendable {
    let suggestedShiftMinutes: Int

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> DriftPayload? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DriftPayload.self, from: data)
    }
}
