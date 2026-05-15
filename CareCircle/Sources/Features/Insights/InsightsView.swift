import SwiftData
import SwiftUI

// MARK: - InsightsView

/// Full chronological list of un-dismissed insights for the active
/// Circle, grouped by severity. Reached from the More tab. Pull-to-
/// refresh forces an immediate recompute; the engine also recomputes
/// on app foreground and after dose-event saves.
struct InsightsView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(InsightsEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @State private var applyTarget: ApplyTarget?

    private var isEntitled: Bool {
        circle.entitles(.insights)
    }

    private var insights: [Insight] {
        circle.insights
            .filter { $0.dismissedAt == nil && $0.appliedAt == nil }
            .sorted {
                if $0.severity.sortRank != $1.severity.sortRank {
                    return $0.severity.sortRank < $1.severity.sortRank
                }
                return $0.computedAt > $1.computedAt
            }
    }

    var body: some View {
        Group {
            if isEntitled {
                entitledBody
            } else {
                PremiumLockedView(
                    feature: .insights,
                    circle: circle,
                    viewerAppleUserID: author.appleUserID
                )
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
    }

    private var entitledBody: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                if insights.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Theme.spacing) {
                        ForEach(insights) { insight in
                            InsightCard(
                                insight: insight,
                                onDismiss: { dismiss(insight) },
                                onApply: insight.payloadJSON != nil
                                    ? { apply(insight) }
                                    : nil
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.spacing)
        }
        .background(Color.ccBackground)
        .refreshable {
            engine.recompute(circle: circle, modelContext: modelContext)
        }
        .navigationDestination(item: $applyTarget) { target in
            destination(for: target)
        }
    }

    @ViewBuilder
    private func destination(for target: ApplyTarget) -> some View {
        switch target {
        case let .medication(id):
            if let medication = circle.medications.first(where: { $0.id == id }) {
                MedicationDetailView(medication: medication, author: author)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text("Nothing to share right now.")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text("Insights appear here as the system spots patterns in your Circle's medication tracking.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
        }
        .padding(.vertical, Theme.looseSpacing)
    }

    private func dismiss(_ insight: Insight) {
        engine.dismiss(insight, modelContext: modelContext)
    }

    private func apply(_ insight: Insight) {
        switch insight.subjectKind {
        case .medication:
            if let subjectId = insight.subjectId {
                applyTarget = .medication(subjectId)
                engine.markApplied(insight, modelContext: modelContext)
            }
        case .careRecipient, .vital, .journalEntry, .circle:
            return
        }
    }

    private enum ApplyTarget: Hashable {
        case medication(UUID)
    }
}
