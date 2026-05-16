import SwiftUI

// MARK: - UpgradeBanner

/// Home-tab teaser that surfaces the paywall for owners of free-tier
/// Circles. Hidden when the Circle is already on a paid tier or when
/// the viewer isn't the owner (only owners can pay).
struct UpgradeBanner: View {
    let circle: Circle
    let viewerAppleUserID: String

    @State private var showPaywall = false

    private var isOwner: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    private var shouldShow: Bool {
        isOwner && circle.subscriptionTier == .free
    }

    var body: some View {
        if shouldShow {
            banner
        }
    }

    private var banner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: Theme.spacing) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.ccPrimary, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock Insights, Bedside, Co-pilot")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text("7-day free trial · See plans")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ccSecondary)
            }
            .padding(Theme.spacing)
            .background(Color.ccSurface, in: .rect(cornerRadius: Theme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens subscription plans")
        .sheet(isPresented: $showPaywall) {
            PaywallView(circle: circle, viewerAppleUserID: viewerAppleUserID)
        }
    }
}
