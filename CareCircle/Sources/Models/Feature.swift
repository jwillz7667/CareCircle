import Foundation

// MARK: - Feature

//
// Single source of truth for which capabilities require a paid tier.
// Anywhere the UI is about to render a gated surface (or the service
// layer is about to do gated work), it should consult
// `feature.requiredTier` and compare to the Circle's current tier.

enum Feature: String, CaseIterable, Sendable, Equatable {
    case sharedCircle
    case bedsideMonitor
    case careCopilot
    case insights
    case unlimitedHistory
    case documentUpload
    case voiceCheckin
    case shiftDigests

    /// Lowest tier that unlocks this feature. `free` means the feature
    /// is always available; `standard` or `premium` mean the Circle's
    /// tier must be at least that level.
    var requiredTier: SubscriptionTier {
        switch self {
        case .sharedCircle: .standard
        case .bedsideMonitor: .premium
        case .careCopilot: .premium
        case .insights: .premium
        case .unlimitedHistory: .premium
        case .documentUpload: .standard
        case .voiceCheckin: .standard
        case .shiftDigests: .standard
        }
    }

    var displayName: String {
        switch self {
        case .sharedCircle: "Shared caregiving Circle"
        case .bedsideMonitor: "Bedside monitor"
        case .careCopilot: "Care Co-pilot"
        case .insights: "Insights & trends"
        case .unlimitedHistory: "Unlimited history"
        case .documentUpload: "Document upload"
        case .voiceCheckin: "Voice check-in"
        case .shiftDigests: "Shift digests"
        }
    }

    /// One-line description used on the paywall feature grid.
    var marketingBlurb: String {
        switch self {
        case .sharedCircle: "Invite caregivers, paid aides, and family."
        case .bedsideMonitor: "Always-on companion screen with one-tap SOS."
        case .careCopilot: "AI assistant for med questions, prep, and recall."
        case .insights: "Daily summaries and trend analysis from your data."
        case .unlimitedHistory: "Keep every activity, vital, and check-in forever."
        case .documentUpload: "Store discharge papers, lab results, ID cards."
        case .voiceCheckin: "Hands-free voice check-ins from any caregiver."
        case .shiftDigests: "Smart shift handoffs across your care team."
        }
    }
}

// MARK: - Tier comparison

nonisolated extension SubscriptionTier: Comparable {
    /// Orders tiers from least privileged to most. Lets feature gates
    /// say `circle.tier >= feature.requiredTier` rather than enumerating
    /// every (tier, feature) pair.
    private var rank: Int {
        switch self {
        case .free: 0
        case .standard: 1
        case .premium: 2
        }
    }

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - Circle feature gate

extension Circle {
    /// True if this Circle currently entitles the given feature.
    /// Combines tier *and* status — an expired Premium circle can't
    /// use Premium features, but a `pastDue` Premium circle still can
    /// (grace period).
    func entitles(_ feature: Feature) -> Bool {
        guard subscriptionStatus.entitlesPaidFeatures else {
            // No paid period → only `free`-tier features.
            return feature.requiredTier == .free
        }
        return subscriptionTier >= feature.requiredTier
    }
}
