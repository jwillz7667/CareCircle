import SwiftData
import SwiftUI

// MARK: - MedsView

struct MedsView: View {
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
                .navigationTitle("Medications")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let circle = activeCircle {
            MedicationListView(circle: circle, author: authorContext)
        } else {
            VStack(spacing: 0) {
                EmptyStateView(
                    systemImage: "pills.fill",
                    title: "No Circle yet",
                    message: "Create a Circle on the Home tab to start tracking medications."
                )

                DisclaimerFooter()
            }
            .background(Color.ccBackground)
        }
    }
}
