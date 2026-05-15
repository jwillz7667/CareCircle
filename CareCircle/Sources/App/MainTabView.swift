import SwiftUI

// MARK: - MainTabView

struct MainTabView: View {
    let authState: AuthState

    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(authState: authState, selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            PulseDashboardView(authState: authState)
                .tabItem {
                    Label("Vitals", systemImage: "heart.fill")
                }
                .tag(AppTab.vitals)

            MedsView(authState: authState)
                .tabItem {
                    Label("Meds", systemImage: "pills.fill")
                }
                .tag(AppTab.meds)

            ChatRoomView(authState: authState)
                .tabItem {
                    Label("Wall", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(AppTab.wall)

            MoreView(authState: authState)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(AppTab.more)
        }
        .tint(Color.ccPrimary)
    }
}
