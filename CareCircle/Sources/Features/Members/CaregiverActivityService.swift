import Foundation

// MARK: - CaregiverActivitySummary

/// Per-caregiver rollup of recent contributions to the Circle. Counts feed
/// activities (notes / photos / voice), paid care minutes, and journal
/// check-ins separately so a row can break the score down — then folds
/// them into a single `score` so members can be sorted and compared.
struct CaregiverActivitySummary: Identifiable, Hashable {
    let appleUserID: String
    let displayName: String
    let activityCount: Int
    let careMinutes: Int
    let journalCount: Int

    /// Weighted score. A daily journal check-in (2 pts) is worth one hour
    /// of feed engagement (~6 short notes), and 60 paid care minutes is
    /// worth ~6 short notes. The point of the formula is not precision —
    /// it's to keep one heavy contribution category from drowning out the
    /// others on the share ring.
    var score: Int {
        activityCount + (journalCount * 2) + (careMinutes / 10)
    }

    var careHours: Double {
        Double(careMinutes) / 60.0
    }

    var id: String {
        appleUserID
    }
}

// MARK: - CaregiverActivityService

/// Pure rollup helper. Walks a Circle's recent activities, care minutes,
/// and journal entries within a window and returns one summary per
/// caregiver in descending score order. Members with no signal in the
/// window still appear (score = 0) so the family sees who's *not*
/// pulling their weight — that's the whole point of a load-balance view.
enum CaregiverActivityService {
    private struct Bucket {
        var displayName: String
        var activities = 0
        var minutes = 0
        var journals = 0
    }

    static func summaries(
        for circle: Circle,
        window: ClosedRange<Date>
    )
        -> [CaregiverActivitySummary]
    {
        let activities = circle.activities.filter { window.contains($0.createdAt) }
        let careEntries = circle.careMinuteEntries.filter { window.contains($0.endedAt) }
        let journal = circle.journalEntries.filter { window.contains($0.recordedAt) }

        let activeMembers = circle.members.filter { $0.status == .active }

        var byID: [String: Bucket] = [:]

        for member in activeMembers where !member.appleUserID.isEmpty {
            byID[member.appleUserID] = Bucket(displayName: member.displayName)
        }

        for entry in activities where !entry.authorAppleUserID.isEmpty {
            let id = entry.authorAppleUserID
            var bucket = byID[id] ?? Bucket(displayName: entry.authorDisplayName)
            bucket.activities += 1
            byID[id] = bucket
        }

        for entry in careEntries where !entry.caregiverAppleUserID.isEmpty {
            let id = entry.caregiverAppleUserID
            var bucket = byID[id] ?? Bucket(displayName: entry.caregiverDisplayName)
            bucket.minutes += entry.durationMinutes
            byID[id] = bucket
        }

        for entry in journal where !entry.authorAppleUserID.isEmpty {
            let id = entry.authorAppleUserID
            var bucket = byID[id] ?? Bucket(displayName: entry.authorDisplayName)
            bucket.journals += 1
            byID[id] = bucket
        }

        let summaries = byID.map { id, bucket in
            CaregiverActivitySummary(
                appleUserID: id,
                displayName: bucket.displayName,
                activityCount: bucket.activities,
                careMinutes: bucket.minutes,
                journalCount: bucket.journals
            )
        }

        return summaries.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Convenience: rolling 7-day window ending at `referenceDate`.
    static func summariesForLastWeek(
        in circle: Circle,
        referenceDate: Date = .now
    )
        -> [CaregiverActivitySummary]
    {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        return summaries(for: circle, window: start ... referenceDate)
    }

    /// Sum of all members' scores. Returned separately so the view can
    /// compute share percentages without re-walking the list.
    static func totalScore(_ summaries: [CaregiverActivitySummary]) -> Int {
        summaries.reduce(0) { $0 + $1.score }
    }
}
