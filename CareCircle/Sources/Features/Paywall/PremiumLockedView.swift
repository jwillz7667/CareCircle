import SwiftUI

// MARK: - PremiumLockedView

//
// Full-screen lock for paid features when the Circle's tier is below
// `feature.requiredTier`. Used for surfaces (Insights, Bedside) where
// a small lock badge would be too subtle — the user has navigated
// into the feature and we want a clear "this is locked" panel with
// an Upgrade CTA, not a half-rendered surface.

struct PremiumLockedView: View {
    let feature: Feature
    let circle: Circle
    let viewerAppleUserID: String

    @State private var showPaywall = false

    private var isOwner: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    var body: some View {
        VStack(spacing: Theme.looseSpacing) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ccPrimary)

            VStack(spacing: Theme.tightSpacing) {
                Text("\(feature.displayName) is a \(feature.requiredTier.displayName) feature")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                    .multilineTextAlignment(.center)
                Text(feature.marketingBlurb)
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
                    .multilineTextAlignment(.center)
            }

            if isOwner {
                Button {
                    showPaywall = true
                } label: {
                    Label("See plans", systemImage: "sparkles")
                }
                .buttonStyle(.ccPrimary)
                .padding(.horizontal, Theme.looseSpacing)
            } else {
                VStack(spacing: 4) {
                    Text("Ask the primary caregiver to upgrade")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text("Only the Circle's owner can change the plan.")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.looseSpacing)
        .background(Color.ccBackground)
        .sheet(isPresented: $showPaywall) {
            PaywallView(circle: circle, viewerAppleUserID: viewerAppleUserID)
        }
    }
}
