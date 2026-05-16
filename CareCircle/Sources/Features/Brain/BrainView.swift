import SwiftData
import SwiftUI

// MARK: - BrainView

/// Tab 3: the shared record. Family Brain is the durable, multi-author
/// substrate for care decisions, doctor conversations, and the day-to-day
/// notes that make a Circle legible to anyone who walks into it.
///
/// This first pass wraps the existing `ActivityFeedView` so the surface
/// exists in the new IA without rebuilding the engine. Subsequent phases
/// add: note templates (daily observation, decision, doctor visit),
/// search across the full record, ER-brief generation, advance directive
/// + insurance attachment, and Apple Health snippet ingestion.
struct BrainView: View {
    let authState: AuthState

    @Query(sort: \Circle.createdAt) private var circles: [Circle]

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var authorContext: ActivityAuthorContext {
        guard case let .signedIn(user) = authState.status else {
            return ActivityAuthorContext(appleUserID: "", displayName: "")
        }
        return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Brain")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.ccBackgroundPrimary, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BrandLogo(size: 28)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let circle = activeCircle {
            ActivityFeedView(circle: circle, author: authorContext)
        } else {
            EmptyStateView(
                systemImage: "brain.head.profile",
                title: "Your Circle's Brain",
                message: "Create a Circle to start the shared record. Notes, photos, voice clips, and decisions land here."
            )
        }
    }
}
