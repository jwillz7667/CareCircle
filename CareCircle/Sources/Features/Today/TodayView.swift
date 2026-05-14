import SwiftData
import SwiftUI

// MARK: - TodayView

/// Tab 2: a chronological mash-up of today's appointments and today's
/// medication doses for the active Circle. Each entry routes to its native
/// detail view (Appointment or Medication).
struct TodayView: View {
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
            VStack(spacing: 0) {
                if let circle = activeCircle {
                    InsightsBanner(circle: circle, author: authorContext)
                        .padding(.horizontal, Theme.spacing)
                        .padding(.top, Theme.tightSpacing)
                }
                content
            }
            .background(Color.ccBackground)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let circle = activeCircle {
            TodayTimelineView(circle: circle, author: authorContext)
        } else {
            EmptyStateView(
                systemImage: "list.bullet.clipboard.fill",
                title: "No Circle yet",
                message: "Create a Circle on the Home tab to see today's plan."
            )
        }
    }
}
