import SwiftData
import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    let authState: AuthState
    @Binding var selectedTab: AppTab

    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @Environment(SOSCenter.self) private var sosCenter
    @State private var isPresentingCreate = false
    @State private var isPresentingSOSCountdown = false

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id })
    }

    private var signedInUser: SignedInUser? {
        if case let .signedIn(user) = authState.status { return user }
        return nil
    }

    private var authorContext: ActivityAuthorContext {
        guard let user = signedInUser else {
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BrandLogo(size: 28)
                    }
                }
        }
        .sheet(isPresented: $isPresentingCreate) {
            CreateCircleView(authState: authState)
        }
        .fullScreenCover(isPresented: $isPresentingSOSCountdown) {
            if let circle = activeCircle, let user = signedInUser {
                SOSCountdownView(circle: circle, user: user, center: sosCenter)
                    .onDisappear { sosCenter.reset() }
            }
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
        VStack(spacing: 0) {
            SOSTriggerButton(isAvailable: signedInUser != nil) {
                isPresentingSOSCountdown = true
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, Theme.tightSpacing)
            .padding(.bottom, Theme.tightSpacing)

            UpgradeBanner(circle: circle, viewerAppleUserID: signedInUser?.id ?? "")
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, Theme.tightSpacing)

            VitalsQuickViewBar(circle: circle) {
                selectedTab = .vitals
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, Theme.tightSpacing)

            JournalTodayCard(circle: circle, author: authorContext)
                .padding(.bottom, Theme.tightSpacing)

            ActivityFeedView(circle: circle, author: authorContext)
        }
        .background(Color.ccBackground)
    }
}
