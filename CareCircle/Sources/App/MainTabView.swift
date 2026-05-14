import SwiftUI

// MARK: - MainTabView

struct MainTabView: View {
    let authState: AuthState

    var body: some View {
        TabView {
            HomeView(authState: authState)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            PulseDashboardView(authState: authState)
                .tabItem {
                    Label("Vitals", systemImage: "heart.fill")
                }

            MedsView(authState: authState)
                .tabItem {
                    Label("Meds", systemImage: "pills.fill")
                }

            ChatRoomView(authState: authState)
                .tabItem {
                    Label("Wall", systemImage: "bubble.left.and.bubble.right.fill")
                }

            MoreView(authState: authState)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .tint(Color.ccPrimary)
    }
}
