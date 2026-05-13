import SwiftUI

// MARK: - MedsView

struct MedsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EmptyStateView(
                    systemImage: "pills.fill",
                    title: "No medications yet",
                    message: "Add a medication to track doses, refills, and history."
                )

                DisclaimerFooter()
            }
            .background(Color.ccBackground)
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }
}

#Preview {
    MedsView()
}
