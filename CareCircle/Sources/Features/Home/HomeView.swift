import SwiftData
import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    let authState: AuthState

    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @State private var isPresentingCreate = false

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id })
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
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
        .sheet(isPresented: $isPresentingCreate) {
            CreateCircleView(authState: authState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let circle = activeCircle {
            populatedHome(for: circle)
        } else {
            emptyHome
        }
    }

    private var emptyHome: some View {
        ZStack(alignment: .bottom) {
            EmptyStateView(
                systemImage: "house.fill",
                title: "Welcome to CareCircle",
                message: "Create your Circle to begin coordinating care with family."
            )

            Button {
                isPresentingCreate = true
            } label: {
                Label("Create your Circle", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.ccPrimary)
            .padding(.horizontal, Theme.looseSpacing)
            .padding(.bottom, Theme.looseSpacing)
        }
    }

    private func populatedHome(for circle: Circle) -> some View {
        ActivityFeedView(circle: circle, author: authorContext)
    }
}
