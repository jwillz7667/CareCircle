import Foundation

// MARK: - SubscriptionDTO

//
// Wire format for `/v1/subscriptions/sync` and `/v1/subscriptions/circle/:id`.
// Mirrors `subscriptionToJson` in `apps/api/src/routes/subscriptions.ts`.
//
// Marked `nonisolated` so the synthesized `Decodable` conformance is
// not tied to the implicit project-wide MainActor isolation —
// `APIClient.send` runs on its actor, off the main thread.

nonisolated struct SubscriptionStateDTO: Decodable, Sendable {
    let circleId: UUID
    let tier: String
    let status: String
    let productId: String?
    let originalTransactionId: String?
    let renewsAt: Date?
    let graceUntil: Date?
    let environment: String?
    let trialUsed: Bool
}

nonisolated struct SubscriptionResponseDTO: Decodable, Sendable {
    let subscription: SubscriptionStateDTO
    let inviteCap: Int
    let seatCap: Int
}

nonisolated struct SubscriptionSyncRequestDTO: Encodable, Sendable {
    let circleId: UUID
    let signedTransaction: String
    let signedRenewalInfo: String?
}
