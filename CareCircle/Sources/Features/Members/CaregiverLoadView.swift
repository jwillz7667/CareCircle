import SwiftData
import SwiftUI

// MARK: - CaregiverLoadView

/// Per-member load-balance view. Renders a ring for each active Circle
/// member showing their share of the last 7 days of care work, plus a
/// breakdown of activities, paid care hours, and journal check-ins.
///
/// The point is *not* to grade anyone — it's a quiet, glance-able way
/// for a family to notice when one person is carrying everything and
/// another hasn't logged anything in a week.
struct CaregiverLoadView: View {
    let circle: Circle

    @State private var referenceDate: Date = .now

    private var summaries: [CaregiverActivitySummary] {
        CaregiverActivityService.summariesForLastWeek(
            in: circle,
            referenceDate: referenceDate
        )
    }

    private var totalScore: Int {
        CaregiverActivityService.totalScore(summaries)
    }

    private var hasAnySignal: Bool {
        totalScore > 0
    }

    var body: some View {
        List {
            Section { headerCard }

            if summaries.isEmpty {
                Section { noMembersContent }
            } else if !hasAnySignal {
                Section { quietWeekContent }
            } else {
                Section("This week") {
                    ForEach(summaries) { summary in
                        CaregiverLoadRow(summary: summary, totalScore: totalScore)
                    }
                }
            }

            Section {
                Text(
                    "Care load is a relative view — it weighs feed activity, paid care minutes, and daily check-ins to suggest where the family might rebalance. It's not a performance review."
                )
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Care load")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .refreshable { referenceDate = .now }
    }

    private var headerCard: some View {
        let totalActivities = summaries.reduce(0) { $0 + $1.activityCount }
        let totalMinutes = summaries.reduce(0) { $0 + $1.careMinutes }
        let totalJournals = summaries.reduce(0) { $0 + $1.journalCount }
        let hours = Double(totalMinutes) / 60.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color.ccPrimary)
                Text("Last 7 days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
            }
            HStack(spacing: 18) {
                stat(value: "\(totalActivities)", label: "posts")
                stat(value: String(format: "%.1fh", hours), label: "care time")
                stat(value: "\(totalJournals)", label: "check-ins")
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ccText)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var noMembersContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("Invite family to your Circle")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text("Once members join, this view will show how the care work is shared.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var quietWeekContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ccSecondary)
            Text("A quiet week")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text(
                "Nothing has been logged in the last 7 days. Drop a note, log care minutes, or run a check-in to get started."
            )
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - CaregiverLoadRow

private struct CaregiverLoadRow: View {
    let summary: CaregiverActivitySummary
    let totalScore: Int

    private var share: Double {
        guard totalScore > 0 else { return 0 }
        return Double(summary.score) / Double(totalScore)
    }

    private var sharePercentLabel: String {
        let pct = Int((share * 100).rounded())
        return "\(pct)%"
    }

    private var hoursLabel: String {
        summary.careMinutes == 0 ? "0h" : String(format: "%.1fh", summary.careHours)
    }

    var body: some View {
        HStack(spacing: 14) {
            CaregiverShareRing(displayName: summary.displayName, share: share)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text("\(summary.activityCount) posts · \(hoursLabel) care · \(summary.journalCount) check-ins")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(sharePercentLabel)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.ccPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ccPrimary.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(summary.displayName): \(sharePercentLabel) of the care load. " +
            "\(summary.activityCount) posts, " +
            "\(hoursLabel) of care time, " +
            "\(summary.journalCount) daily check-ins."
    }
}
