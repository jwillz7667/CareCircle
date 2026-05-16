import SwiftUI

// MARK: - MainTabView

struct MainTabView: View {
    let authState: AuthState

    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(authState: authState, selectedTab: $selectedTab)
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
                .tag(AppTab.today)

            MedsView(authState: authState)
                .tabItem {
                    Label("Meds", systemImage: "pills.fill")
                }
                .tag(AppTab.meds)

            BrainView(authState: authState)
                .tabItem {
                    Label("Brain", systemImage: "brain.head.profile")
                }
                .tag(AppTab.brain)

            MoreView(authState: authState)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(AppTab.more)
        }
        .tint(Color.ccAccent)
    }
}
