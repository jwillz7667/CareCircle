import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "house.fill",
                title: "Welcome to CareCircle",
                message: "Record your first handoff to keep everyone aligned."
            )
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }
}

#Preview {
    HomeView()
}
