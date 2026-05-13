import SwiftUI

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.ccPrimary)
                .accessibilityHidden(true)

            VStack(spacing: Theme.tightSpacing) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.ccSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.looseSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ccBackground)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "house.fill",
        title: "Welcome to CareCircle",
        message: "Record your first handoff to get started."
    )
}
