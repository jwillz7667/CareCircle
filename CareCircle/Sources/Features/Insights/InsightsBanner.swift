import SwiftUI

// MARK: - InsightsBanner

/// Inline preview of the single most important un-dismissed insight,
/// surfaced at the top of `TodayView`. Tapping pushes the full list.
/// Renders nothing when there's nothing worth surfacing so the layout
/// stays clean for empty Circles.
struct InsightsBanner: View {
    let circle: Circle
    let author: ActivityAuthorContext

    private var topInsight: Insight? {
        circle.insights
            .filter { $0.dismissedAt == nil && $0.appliedAt == nil }
            .min {
                if $0.severity.sortRank != $1.severity.sortRank {
                    return $0.severity.sortRank < $1.severity.sortRank
                }
                return $0.computedAt > $1.computedAt
            }
    }

    var body: some View {
        if let topInsight {
            NavigationLink {
                InsightsView(circle: circle, author: author)
            } label: {
                InsightCard(insight: topInsight, compact: true)
            }
            .buttonStyle(.plain)
        }
    }
}
