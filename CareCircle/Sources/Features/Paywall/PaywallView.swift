import StoreKit
import SwiftUI

// MARK: - PaywallView

//
// Tier-comparison paywall surfaced when the owner of a Circle tries
// to use a paid feature, or directly from `MoreView ▸ Subscription`.
// Non-owners are shown a different message (see `OwnerOnlyPaywallView`)
// because only the owner can pay.
//
// 7-day intro offer is fulfilled by StoreKit — we don't gate it
// ourselves. The product configuration in App Store Connect (and in
// `CareCircle.storekit` for dev) declares the offer; we render the
// "7-day free trial" copy only when `Product.SubscriptionInfo.IntroductoryOffer`
// is present and not yet used by this Apple ID.

struct PaywallView: View {
    let circle: Circle
    let viewerAppleUserID: String

    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var pendingTier: SubscriptionTier?

    private var isOwner: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    var body: some View {
        NavigationStack {
            if isOwner {
                ownerBody
            } else {
                OwnerOnlyPaywallView(circle: circle)
            }
        }
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .background(Color.ccBackground)
    }

    private var ownerBody: some View {
        ScrollView {
            VStack(spacing: Theme.looseSpacing) {
                header
                tierCards
                trialFootnote
                restoreLink
                disclaimer
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.spacing)
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text("Care for everyone, in one Circle.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text("Pick a plan to invite caregivers, share check-ins, and unlock the Care Co-pilot.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tierCards: some View {
        VStack(spacing: Theme.spacing) {
            ForEach(purchasableTiers, id: \.self) { tier in
                TierCardView(
                    tier: tier,
                    product: subscriptions.products[tier.productID ?? ""],
                    isCurrent: circle.subscriptionTier == tier,
                    isHighlighted: tier == .premium,
                    trialAvailable: trialIsAvailable(for: tier),
                    purchaseState: subscriptions.purchaseState,
                    onPurchase: { tap(tier: tier) }
                )
            }
        }
    }

    @ViewBuilder
    private var trialFootnote: some View {
        if !circle.trialUsed, purchasableTiers.contains(where: trialIsAvailable(for:)) {
            HStack(spacing: Theme.tightSpacing) {
                Image(systemName: "gift")
                    .foregroundStyle(Color.ccPrimary)
                Text("Your first 7 days are free — cancel anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var restoreLink: some View {
        Button {
            Task { await subscriptions.restore(for: circle) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Restore purchases")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.ccPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text(
            "Subscriptions auto-renew unless canceled at least 24 hours before the end of the current period. Manage or cancel in your Apple ID Settings. The Care Recipient never pays — only the Primary Caregiver does."
        )
        .font(.caption)
        .foregroundStyle(Color.ccSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchasableTiers: [SubscriptionTier] {
        SubscriptionTier.allCases.filter { $0 != .free }
    }

    private func trialIsAvailable(for tier: SubscriptionTier) -> Bool {
        guard !circle.trialUsed else { return false }
        guard let product = subscriptions.products[tier.productID ?? ""] else { return false }
        return product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    private func tap(tier: SubscriptionTier) {
        pendingTier = tier
        Task {
            await subscriptions.purchase(tier: tier, for: circle)
            if case let .succeeded(productID) = subscriptions.purchaseState,
               productID == tier.productID
            {
                dismiss()
            }
            pendingTier = nil
        }
    }
}

// MARK: - TierCardView

private struct TierCardView: View {
    let tier: SubscriptionTier
    let product: Product?
    let isCurrent: Bool
    let isHighlighted: Bool
    let trialAvailable: Bool
    let purchaseState: SubscriptionService.PurchaseState
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
                priceLabel
            }
            Text(tier.tagline)
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
            featureList
            actionButton
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .stroke(Color.ccPrimary, lineWidth: 2)
            }
        }
    }

    private var priceLabel: some View {
        Text(product?.displayPrice ?? tier.fallbackMonthlyPrice)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.ccText)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            ForEach(featuresForTier, id: \.self) { feature in
                HStack(alignment: .top, spacing: Theme.tightSpacing) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.ccPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.ccText)
                        Text(feature.marketingBlurb)
                            .font(.caption)
                            .foregroundStyle(Color.ccSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isCurrent {
            Text("Current plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ccPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(Color.ccPrimary, lineWidth: 1.5)
                }
        } else {
            Button(action: onPurchase) {
                HStack {
                    if isPurchasingThisTier {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(isHighlighted ? .ccPrimary : .ccSecondary)
            .disabled(isPurchasingAny)
        }
    }

    private var buttonTitle: String {
        if trialAvailable {
            return "Start 7-day free trial"
        }
        return "Upgrade to \(tier.displayName)"
    }

    private var isPurchasingThisTier: Bool {
        if case let .purchasing(t) = purchaseState { return t == tier }
        return false
    }

    private var isPurchasingAny: Bool {
        switch purchaseState {
        case .purchasing, .restoring: true
        default: false
        }
    }

    private var featuresForTier: [Feature] {
        Feature.allCases.filter { $0.requiredTier == tier || $0.requiredTier < tier }
    }
}

// MARK: - OwnerOnlyPaywallView

private struct OwnerOnlyPaywallView: View {
    let circle: Circle

    var body: some View {
        VStack(spacing: Theme.looseSpacing) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Color.ccPrimary)
            Text("Ask \(circle.name)'s owner to upgrade")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.center)
            Text(
                "The primary caregiver pays for the Circle's subscription. Only they can change the plan from their device."
            )
            .font(.subheadline)
            .foregroundStyle(Color.ccSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(Theme.looseSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ccBackground)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
    }
}
