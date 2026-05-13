import SwiftUI

// MARK: - TodayView

struct TodayView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "list.bullet.clipboard.fill",
                title: "Nothing scheduled",
                message: "Today's tasks and reminders will appear here."
            )
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }
}

#Preview {
    TodayView()
}
