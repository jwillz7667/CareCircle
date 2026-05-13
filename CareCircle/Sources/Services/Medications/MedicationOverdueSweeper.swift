import Foundation
import OSLog
import SwiftData

// MARK: - MedicationOverdueSweeper

/// Reconciles dose history when the app comes back to the foreground.
/// - Creates `DoseEvent`s for past scheduled times (medication just added,
///   or device was offline) and marks them `.missed` if older than the
///   grace window, otherwise `.scheduled`.
/// - Bumps `.scheduled` doses older than the grace window to `.missed`.
@MainActor
struct MedicationOverdueSweeper {
    var gracePeriodMinutes = 60
    var lookbackDays = 7
    private let logger = AppLogger.app

    func sweep(in context: ModelContext) {
        let descriptor = FetchDescriptor<Medication>()
        do {
            let medications = try context.fetch(descriptor)
            let now = Date()
            let graceCutoff = now.addingTimeInterval(-Double(gracePeriodMinutes) * 60)
            let lookbackCutoff = Calendar.current.date(
                byAdding: .day,
                value: -lookbackDays,
                to: now
            ) ?? now

            for medication in medications where medication.status == .active {
                synthesizeMissedOccurrences(
                    for: medication,
                    between: lookbackCutoff,
                    and: graceCutoff,
                    in: context
                )
            }
            promoteScheduledToMissed(graceCutoff: graceCutoff, in: context)
            try context.save()
        } catch {
            logger.error(
                "Overdue sweep failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func synthesizeMissedOccurrences(
        for medication: Medication,
        between start: Date,
        and end: Date,
        in context: ModelContext
    ) {
        guard medication.schedule.frequency != .asNeeded else { return }
        let occurrences = computeOccurrences(
            for: medication.schedule,
            between: start,
            and: end
        )
        for occurrence in occurrences {
            DoseEventApplicator.apply(
                status: .missed,
                scheduledAt: occurrence,
                medication: medication,
                in: context,
                marker: nil
            )
        }
    }

    private func promoteScheduledToMissed(graceCutoff: Date, in context: ModelContext) {
        let descriptor = FetchDescriptor<DoseEvent>(
            predicate: #Predicate { event in
                event.scheduledAt < graceCutoff && event.statusRaw == "scheduled"
            }
        )
        guard let stale = try? context.fetch(descriptor) else { return }
        for event in stale {
            event.status = .missed
            event.updatedAt = .now
        }
    }

    private func computeOccurrences(
        for schedule: MedicationSchedule,
        between start: Date,
        and end: Date,
        calendar: Calendar = .current
    )
        -> [Date]
    {
        guard !schedule.timesOfDay.isEmpty, schedule.frequency != .asNeeded else { return [] }
        var results: [Date] = []
        var day = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while day <= endDay {
            let weekday = calendar.component(.weekday, from: day)
            let weekdayAllowed = schedule.frequency != .weekly
                || schedule.daysOfWeek.isEmpty
                || schedule.daysOfWeek.contains(weekday)
            if weekdayAllowed {
                for time in schedule.timesOfDay {
                    if let occurrence = calendar.date(
                        bySettingHour: time.hour,
                        minute: time.minute,
                        second: 0,
                        of: day
                    ), occurrence > start, occurrence <= end {
                        results.append(occurrence)
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }
}
