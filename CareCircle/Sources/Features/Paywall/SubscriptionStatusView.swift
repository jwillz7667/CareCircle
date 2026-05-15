import StoreKit
import SwiftUI

// MARK: - SubscriptionStatusView

//
// Manages the current Circle's subscription. Renders the active tier
// + status, links to the paywall (owner) or shows a read-only summary
// (non-owner), and surfaces the system "Manage subscription" sheet so
// the owner can change or cancel without leaving the app.

struct SubscriptionStatusView: View {
    let circle: Circle
    let viewerAppleUserID: String

    @Environment(SubscriptionService.self) private var subscriptions
    @State private var showPaywall = false
    @State private var showManage = false

    private var isOwner: Bool {
        circle.ownerAppleUserID == viewerAppleUserID
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                    HStack {
                        Text(circle.subscriptionTier.displayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.ccText)
                        Spacer()
                        statusBadge
                    }
                    Text(circle.subscriptionTier.tagline)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                    if let renewsAt = circle.subscriptionRenewsAt {
                        Text(renewalLine(for: renewsAt))
                            .font(.footnote)
                            .foregroundStyle(Color.ccSecondary)
                    }
                }
                .padding(.vertical, Theme.tightSpacing)
            }

            if circle.subscriptionStatus.needsBillingAttention {
                Section {
                    Label(
                        "Payment retry — please update your payment method in Apple ID Settings.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(Color.ccDanger)
                }
            }

            Section("Seats") {
                LabeledContent(
                    "Members in this Circle",
                    value: "\(circle.members.count) / \(circle.subscriptionTier.seatCap)"
                )
                .foregroundStyle(Color.ccText)
                LabeledContent("Invites you can send", value: "\(circle.subscriptionTier.inviteCap)")
                    .foregroundStyle(Color.ccText)
            }

            if isOwner {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        Label(actionButtonTitle, systemImage: actionButtonIcon)
                    }
                    .buttonStyle(.ccPrimary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)

                    if circle.subscriptionTier != .free {
                        Button {
                            showManage = true
                        } label: {
                            Label("Manage subscription", systemImage: "gearshape")
                                .foregroundStyle(Color.ccPrimary)
                        }
                    }
                }
            } else {
                Section {
                    Text("Only \(circle.name)'s primary caregiver can change this plan.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .task {
            await subscriptions.hydrate(circleID: circle.id)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(circle: circle, viewerAppleUserID: viewerAppleUserID)
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
    }

    private var statusBadge: some View {
        Text(circle.subscriptionStatus.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(badgeColor.opacity(0.18))
            }
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch circle.subscriptionStatus {
        case .trialing, .active: Color.ccPrimary
        case .pastDue: Color.ccDanger
        case .canceled: Color.ccSecondary
        case .expired: Color.ccSecondary
        }
    }

    private var actionButtonTitle: String {
        if circle.subscriptionTier == .free {
            return "See plans"
        }
        return "Change plan"
    }

    private var actionButtonIcon: String {
        circle.subscriptionTier == .free ? "sparkles" : "arrow.up.right.circle"
    }

    private func renewalLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let label = switch circle.subscriptionStatus {
        case .trialing: "Trial ends"
        case .active: "Renews"
        case .pastDue: "Retry through"
        case .canceled: "Ends"
        case .expired: "Ended"
        }
        return "\(label) \(formatter.string(from: date))"
    }
}
