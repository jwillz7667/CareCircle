import Foundation

// MARK: - SubscriptionTier

//
// Owner-pays, per-Circle subscription tier. Every member of a Circle sees
// the same tier — the *owner's* purchase is what gates Premium features
// for everyone. Raw strings match the backend `subscription_tier` enum
// and the Postgres trigger that enforces the seat cap, so adding a tier
// requires coordinated changes in three places (here, `schema.ts`,
// `enforce_circle_member_cap`).

enum SubscriptionTier: String, Codable, CaseIterable, Sendable, Equatable {
    case free
    case standard
    case premium

    /// Number of *additional* people the owner can invite into the Circle,
    /// including the care recipient seat. Seat cap = `inviteCap + 1`
    /// (the owner themselves).
    var inviteCap: Int {
        switch self {
        case .free: 0
        case .standard: 6
        case .premium: 15
        }
    }

    /// Total people who can sit inside a single Circle on this tier
    /// (owner + everyone they've invited).
    var seatCap: Int {
        inviteCap + 1
    }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .standard: "Standard"
        case .premium: "Premium"
        }
    }

    /// Marketing copy used on the paywall — short enough to fit a
    /// pricing card subtitle.
    var tagline: String {
        switch self {
        case .free: "Solo caregiver, no sharing"
        case .standard: "Up to 6 caregivers + care recipient"
        case .premium: "Up to 15 caregivers + care recipient"
        }
    }

    /// USD price for the monthly auto-renewable subscription. UI uses
    /// StoreKit's localized `displayPrice` when a `Product` is loaded;
    /// this is a fallback for offline / loading states.
    var fallbackMonthlyPrice: String {
        switch self {
        case .free: "Free"
        case .standard: "$19.99 / month"
        case .premium: "$39.99 / month"
        }
    }

    /// The StoreKit product ID this tier maps to. Must match
    /// `STOREKIT_PRODUCT_*` on the backend and the products in the
    /// `Configuration.storekit` test file.
    var productID: String? {
        switch self {
        case .free: nil
        case .standard: "app.carecircle.subscription.standard.monthly"
        case .premium: "app.carecircle.subscription.premium.monthly"
        }
    }
}
