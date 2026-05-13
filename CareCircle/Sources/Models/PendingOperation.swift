import Foundation
import SwiftData

// MARK: - PendingOperation

/// Durable client-side op queue entry. Each entry is an opaque mutation
/// destined for `POST /v1/sync/batch`. The clientOpId is the server's
/// idempotency key — keep it stable across retries.
@Model
final class PendingOperation {
    var id = UUID()
    var clientOpId = UUID()
    var operationType = ""
    var circleId: UUID?
    var payloadJSON = Data()
    var createdAt = Date.now
    var lastAttemptAt: Date?
    var attemptCount = 0
    var lastErrorMessage: String?

    init(
        clientOpId: UUID = UUID(),
        operationType: String,
        circleId: UUID?,
        payloadJSON: Data,
        createdAt: Date = .now
    ) {
        self.clientOpId = clientOpId
        self.operationType = operationType
        self.circleId = circleId
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}
