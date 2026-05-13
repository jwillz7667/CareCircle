import SwiftUI

// MARK: - MainTabView

struct MainTabView: View {
    let authState: AuthState

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            TodayView()
                .tabItem {
                    Label("Today", systemImage: "list.bullet.clipboard.fill")
                }

            MedsView()
                .tabItem {
                    Label("Meds", systemImage: "pills.fill")
                }

            MoreView(authState: authState)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .tint(Color.ccPrimary)
    }
}
