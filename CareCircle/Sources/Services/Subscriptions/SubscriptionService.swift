import Foundation
import OSLog
import StoreKit
import SwiftData

// MARK: - SubscriptionService

//
// Owns StoreKit 2 for owner-paid, per-Circle subscriptions: loads
// products, listens to `Transaction.updates` for external renewals/
// refunds, drives purchases bound to a Circle via `appAccountToken`,
// and mirrors every verified transaction to `POST /v1/subscriptions/
// sync`. The backend is the source of truth; its response writes back
// into the local SwiftData `Circle`. Non-owners read state via
// `/v1/subscriptions/circle/:id` and can't initiate a purchase.

@Observable
@MainActor
final class SubscriptionService {
    /// Loaded products, keyed by `Product.id`. Empty on init; populated
    /// once `loadProducts` completes. UI must tolerate `nil` lookups
    /// during the brief window before products arrive.
    private(set) var products: [String: Product] = [:]

    /// Status of the most recent `purchase()` call. UI binds to this
    /// to show progress / errors. `.idle` between attempts.
    private(set) var purchaseState: PurchaseState = .idle

    /// Last time we successfully synced any transaction to the backend.
    /// Used by debug surfaces; not load-bearing for correctness.
    private(set) var lastSyncedAt: Date?

    private let apiClient: APIClient
    private let modelContainer: ModelContainer
    private var updatesTask: Task<Void, Never>?

    init(apiClient: APIClient, modelContainer: ModelContainer) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: Lifecycle

    /// Starts the long-running `Transaction.updates` listener, kicks off
    /// product loading, and replays any transactions we failed to ship
    /// to the backend on a previous launch. Idempotent. Call from
    /// `RootView.task` (or app-launch hook); never from a per-view
    /// `.task` modifier.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProducts()
        }
        Task { [weak self] in
            await self?.drainUnfinishedTransactions()
        }
    }

    /// Stops the listener. Safe to call multiple times; cancels the
    /// task created by `start()`.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: Products

    /// Pulls the two tier products from the App Store. Retries with
    /// exponential backoff on transient errors, capped at three
    /// attempts. Permanent errors (no products configured) are logged
    /// and leave `products` empty — the paywall will show fallback
    /// pricing.
    func loadProducts() async {
        let productIDs = SubscriptionTier.allCases.compactMap(\.productID)
        guard !productIDs.isEmpty else { return }

        var attempt = 0
        while attempt < 3 {
            attempt += 1
            do {
                let result = try await Product.products(for: productIDs)
                products = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
                AppLogger.subscriptions.info(
                    "Loaded \(result.count, privacy: .public) StoreKit products."
                )
                return
            } catch {
                AppLogger.subscriptions.error(
                    "StoreKit product load failed (attempt \(attempt, privacy: .public)): \(String(describing: error), privacy: .public)"
                )
                if attempt < 3 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    // MARK: Purchase

    /// Initiates the StoreKit purchase flow for `tier` and binds the
    /// resulting subscription to `circle`. The circle's UUID is encoded
    /// as `appAccountToken` so Apple's webhook can resolve the binding
    /// later without consulting our DB.
    ///
    /// Never throws on user-cancel — only on programmer/system errors.
    /// Updates `purchaseState`; UI binds to that.
    func purchase(
        tier: SubscriptionTier,
        for circle: Circle
    ) async {
        guard let productID = tier.productID else {
            purchaseState = .failed("This tier is not purchasable.")
            return
        }
        guard let product = products[productID] else {
            purchaseState = .failed("Product still loading — try again in a moment.")
            return
        }
        purchaseState = .purchasing(tier: tier)

        do {
            let result = try await product.purchase(options: [
                .appAccountToken(circle.id),
            ])
            switch result {
            case let .success(verification):
                await handlePurchaseSuccess(
                    verification: verification,
                    circleID: circle.id,
                    product: product
                )
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            @unknown default:
                purchaseState = .failed("Unknown purchase result.")
            }
        } catch {
            AppLogger.subscriptions.error(
                "Purchase failed: \(String(describing: error), privacy: .public)"
            )
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Re-checks `Transaction.currentEntitlements` and re-syncs each one
    /// with the backend. Surfaced from the paywall's "Restore Purchases"
    /// link — required for App Review and for users who reinstall.
    /// Sync failures are logged but don't fail the restore — we don't
    /// want to surface "restore failed" when the user has a valid
    /// entitlement that just couldn't reach our backend this second.
    func restore(for circle: Circle) async {
        purchaseState = .restoring
        var restoredAny = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                do {
                    try await syncVerifiedTransaction(
                        verification: result,
                        transaction: transaction,
                        circleID: circle.id
                    )
                    restoredAny = true
                } catch {
                    AppLogger.subscriptions.error(
                        "Restore: sync failed for transaction \(transaction.id, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
        purchaseState = restoredAny ? .restored : .idle
    }

    // MARK: Hydration

    /// Pulls the current subscription state for `circle` from the
    /// backend and writes it into SwiftData. Called by `BackendHydrator`
    /// on app foreground and after sign-in — keeps non-owner devices
    /// in sync with the owner's subscription without depending on
    /// StoreKit reads (which only work on the owner's device).
    func hydrate(circleID: UUID) async {
        do {
            let response: SubscriptionResponseDTO = try await apiClient.send(
                method: .get,
                path: "/v1/subscriptions/circle/\(circleID.uuidString)"
            )
            applyResponseToLocalCircle(response, circleID: circleID)
        } catch {
            AppLogger.subscriptions.error(
                "Failed to hydrate subscription for circle \(circleID.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Private

    /// Replays transactions we never managed to call `finish()` on —
    /// i.e. ones where a previous `sync` to the backend failed (network
    /// blip, backend 5xx, auth expired mid-purchase). Without this, a
    /// transient failure on purchase day would leave the user paid on
    /// Apple's side but on the free tier on ours forever.
    private func drainUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            await processIncomingTransaction(result, source: "drain")
        }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            await processIncomingTransaction(result, source: "updates")
        }
    }

    /// Shared handler for any `VerificationResult<Transaction>` arriving
    /// from `Transaction.updates` or `Transaction.unfinished`. Verified
    /// + bound transactions go to the backend; on success we `finish()`,
    /// on failure we leave the transaction unfinished so the next launch
    /// picks it up again. Unverified payloads and orphan-circle payloads
    /// are finished to keep the queue from growing forever.
    private func processIncomingTransaction(
        _ result: VerificationResult<Transaction>,
        source: String
    ) async {
        switch result {
        case let .verified(transaction):
            guard let circleID = transaction.appAccountToken else {
                AppLogger.subscriptions.warning(
                    "\(source, privacy: .public): transaction \(transaction.originalID, privacy: .public) has no appAccountToken — finishing to clear queue."
                )
                await transaction.finish()
                return
            }
            do {
                try await syncVerifiedTransaction(
                    verification: result,
                    transaction: transaction,
                    circleID: circleID
                )
                await transaction.finish()
            } catch {
                AppLogger.subscriptions.error(
                    "\(source, privacy: .public): failed to sync \(transaction.id, privacy: .public): \(String(describing: error), privacy: .public). Leaving unfinished for retry."
                )
            }
        case let .unverified(transaction, error):
            AppLogger.subscriptions.warning(
                "\(source, privacy: .public): discarding unverified transaction \(transaction.originalID, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            await transaction.finish()
        }
    }

    private func handlePurchaseSuccess(
        verification: VerificationResult<Transaction>,
        circleID: UUID,
        product: Product
    ) async {
        switch verification {
        case let .verified(transaction):
            do {
                try await syncVerifiedTransaction(
                    verification: verification,
                    transaction: transaction,
                    circleID: circleID
                )
                await transaction.finish()
                purchaseState = .succeeded(productID: product.id)
            } catch {
                AppLogger.subscriptions.error(
                    "Backend sync failed after purchase \(transaction.id, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                // Do NOT finish — we'll retry via `Transaction.unfinished`
                // on the next launch, and the entitlement keeps working
                // on Apple's side regardless. Surface the failure so the
                // owner can hit "Restore" or relaunch.
                purchaseState = .failed(
                    "Your purchase went through Apple, but we couldn't reach CareCircle. Open the app again on this device — we'll finish setting things up automatically."
                )
            }
        case let .unverified(transaction, error):
            AppLogger.subscriptions.error(
                "Unverified transaction after purchase \(transaction.originalID, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            // Apple's own verifier failed — we can't credit this, but we
            // must finish it or StoreKit will redeliver it on every
            // launch.
            await transaction.finish()
            purchaseState = .failed("Could not verify Apple's signature on the transaction.")
        }
    }

    /// Sends a verified StoreKit transaction (and renewal info if
    /// available) to the backend, then writes the backend's response
    /// into the local SwiftData `Circle` so the UI updates.
    ///
    /// Throws on any backend-side failure. The caller decides whether to
    /// `Transaction.finish()` — we only call `finish()` after success so
    /// StoreKit re-delivers via `Transaction.unfinished` if we never
    /// reach the backend.
    ///
    /// Takes the `VerificationResult` envelope rather than the unwrapped
    /// `Transaction` because the JWS string the backend re-verifies
    /// lives on the envelope (`VerificationResult.jwsRepresentation`),
    /// not on the decoded payload.
    private func syncVerifiedTransaction(
        verification: VerificationResult<Transaction>,
        transaction: Transaction,
        circleID: UUID
    ) async throws {
        let transactionJWS = verification.jwsRepresentation
        let renewalJWS = await renewalJWS(for: transaction)

        let request = SubscriptionSyncRequestDTO(
            circleId: circleID,
            signedTransaction: transactionJWS,
            signedRenewalInfo: renewalJWS
        )

        let response: SubscriptionResponseDTO = try await apiClient.send(
            method: .post,
            path: "/v1/subscriptions/sync",
            body: request
        )
        applyResponseToLocalCircle(response, circleID: circleID)
        lastSyncedAt = .now
        AppLogger.subscriptions.info(
            "Synced transaction \(transaction.id, privacy: .public) → tier=\(response.subscription.tier, privacy: .public) status=\(response.subscription.status, privacy: .public)"
        )
    }

    // MARK: Nested types

    enum PurchaseState: Equatable, Sendable {
        case idle
        case purchasing(tier: SubscriptionTier)
        case pending
        case succeeded(productID: String)
        case restoring
        case restored
        case failed(String)
    }
}

// MARK: - Storage helpers

private extension SubscriptionService {
    /// JWS for the renewal info attached to this transaction's
    /// subscription. The renewal info's JWS lives on the enclosing
    /// `VerificationResult`, not the decoded payload. Returns nil when
    /// the subscription has no renewal info yet (one-shot transactions,
    /// refunds in flight) — the backend tolerates a missing renewal.
    func renewalJWS(for transaction: Transaction) async -> String? {
        guard let statuses = await transaction.subscriptionStatus else { return nil }
        return statuses.renewalInfo.jwsRepresentation
    }

    /// Writes the backend's authoritative subscription state into the
    /// local Circle row using a dedicated background `ModelContext` so
    /// we don't race the UI's context.
    func applyResponseToLocalCircle(
        _ response: SubscriptionResponseDTO,
        circleID: UUID
    ) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Circle>(
            predicate: #Predicate { $0.id == circleID }
        )
        guard let circles = try? context.fetch(descriptor), let circle = circles.first else {
            // Circle hasn't been hydrated locally yet — the next
            // BackendHydrator pass will pull it down with the fresh
            // subscription columns included.
            return
        }
        circle.subscriptionTierRaw = response.subscription.tier
        circle.subscriptionStatusRaw = response.subscription.status
        circle.subscriptionProductID = response.subscription.productId
        circle.subscriptionOriginalTransactionID = response.subscription.originalTransactionId
        circle.subscriptionRenewsAt = response.subscription.renewsAt
        circle.subscriptionGraceUntil = response.subscription.graceUntil
        circle.subscriptionEnvironment = response.subscription.environment
        circle.trialUsed = response.subscription.trialUsed
        do {
            try context.save()
        } catch {
            AppLogger.subscriptions.error(
                "Failed to persist subscription state: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
