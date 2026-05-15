import Foundation

// MARK: - SubscriptionStatus

//
// Lifecycle state of the Circle's paid subscription. Mirrors the
// backend `subscription_status` enum used by the StoreKit verifier and
// the App Store Server Notifications V2 webhook handler.
//
// - `trialing`: inside the 7-day introductory free trial
// - `active`: paid period in effect, will renew at `renewsAt`
// - `pastDue`: renewal failed, Apple is in billing retry (grace period)
// - `canceled`: user turned off auto-renew but paid period not over yet
// - `expired`: paid period elapsed without renewal — back to free tier

enum SubscriptionStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case trialing
    case active
    case pastDue = "past_due"
    case canceled
    case expired

    /// True if the Circle currently enjoys paid-tier privileges. Both
    /// `canceled` and `pastDue` are still inside a paid period — the
    /// user paid through the end of the billing cycle.
    var entitlesPaidFeatures: Bool {
        switch self {
        case .trialing, .active, .canceled, .pastDue: true
        case .expired: false
        }
    }

    var displayName: String {
        switch self {
        case .trialing: "Free trial"
        case .active: "Active"
        case .pastDue: "Payment retry"
        case .canceled: "Canceled"
        case .expired: "Expired"
        }
    }

    /// Whether the owner should see a "fix your payment method" nudge.
    var needsBillingAttention: Bool {
        self == .pastDue
    }
}
