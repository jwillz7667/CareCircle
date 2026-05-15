import SwiftUI

// MARK: - FeatureGate

//
// `.featureGate(_:circle:viewerAppleUserID:)` wraps a tap target so
// that:
//
//   • when the Circle's tier entitles the feature, the wrapped view's
//     gestures run unchanged;
//   • otherwise the underlying gestures are suppressed and a tap
//     presents the paywall.
//
// Use it on tap-driven views — `Button { … }`, `NavigationLink { … }`,
// custom tappable cards. The gate also paints a small lock badge in
// the top-right corner when locked.

struct FeatureGate: ViewModifier {
    let feature: Feature
    let circle: Circle
    let viewerAppleUserID: String

    @State private var showPaywall = false

    func body(content: Content) -> some View {
        let entitled = circle.entitles(feature)
        ZStack(alignment: .topTrailing) {
            content
                .allowsHitTesting(entitled)
                .opacity(entitled ? 1.0 : 0.55)
            if !entitled {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showPaywall = true }
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.ccPrimary, in: .circle)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(circle: circle, viewerAppleUserID: viewerAppleUserID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(entitled ? [] : [.isButton])
        .accessibilityLabel(entitled ? "" :
            "Locked — \(feature.displayName) requires \(feature.requiredTier.displayName)")
    }
}

extension View {
    /// Gates this view behind a feature's required subscription tier.
    /// When locked, taps present the paywall instead of the wrapped
    /// action. Shows a small lock badge in the top-right.
    func featureGate(
        _ feature: Feature,
        circle: Circle,
        viewerAppleUserID: String
    )
        -> some View
    {
        modifier(FeatureGate(
            feature: feature,
            circle: circle,
            viewerAppleUserID: viewerAppleUserID
        ))
    }

    /// Convenience overload for views whose Circle context may be
    /// unresolved (e.g. an empty-state screen). When `circle` is nil
    /// the view passes through untouched.
    @ViewBuilder
    func featureGateIfPresent(
        _ feature: Feature,
        circle: Circle?,
        viewerAppleUserID: String
    )
        -> some View
    {
        if let circle {
            featureGate(feature, circle: circle, viewerAppleUserID: viewerAppleUserID)
        } else {
            self
        }
    }
}
