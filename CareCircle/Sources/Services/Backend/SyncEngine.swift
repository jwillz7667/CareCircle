import Foundation
import OSLog
import SwiftData

// MARK: - SyncEngine

/// Drains the durable `PendingOperation` queue to the Railway backend.
///
/// The engine is the single owner of the write-through path: features
/// keep using SwiftData/CloudKit as today, then call
/// `enqueueActivityCreate(_:)` (or future siblings) which appends a
/// `PendingOperation` row and triggers a drain. Idempotency is provided
/// by the per-op `clientOpId` — replays after a crash or a 5xx never
/// duplicate server-side rows.
///
/// Concurrent drain attempts are coalesced via `inFlightDrain`. On
/// success, ack'd rows are deleted; on auth failure the engine flips to
/// `.offline` and waits for the next trigger (foreground, sign-in, or
/// manual retry).
@Observable
@MainActor
final class SyncEngine {
    enum Status: Equatable, Sendable {
        case idle
        case draining
        case offline
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var pendingCount = 0

    private let apiClient: APIClient
    private let modelContainer: ModelContainer
    private let encoder: JSONEncoder

    private var inFlightDrain: Task<Void, Never>?

    /// `POST /v1/sync/batch` accepts at most 100 ops per call; chunk
    /// below that to keep payloads under the API's 1 MB body cap with
    /// room for future per-op growth.
    private static let batchChunkSize = 50

    init(
        apiClient: APIClient,
        modelContainer: ModelContainer
    ) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncEngine.isoFormatter.string(from: date))
        }
        self.encoder = encoder
    }

    /// Refreshes the cached `pendingCount` from the durable queue. Cheap
    /// — call from view models that surface the count.
    func refreshPendingCount() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<PendingOperation>()
        do {
            pendingCount = try context.fetchCount(descriptor)
        } catch {
            AppLogger.sync.error(
                "Failed to fetch pending op count: \(String(describing: error), privacy: .public)"
            )
            pendingCount = 0
        }
    }

    /// Enqueues a backend mirror for an activity that was just written
    /// to SwiftData. Returns immediately — actual transport happens in
    /// the next drain pass.
    func enqueueActivityCreate(_ activity: Activity) {
        let payload = CreateActivityPayload(
            activityId: activity.id,
            type: activity.type.rawValue,
            body: activity.body,
            createdAt: activity.createdAt,
            authorAppleUserID: activity.authorAppleUserID,
            authorDisplayName: activity.authorDisplayName,
            audioDurationSeconds: activity.audioDurationSeconds,
            extractedEntitiesJSON: activity.extractedEntitiesJSON
        )

        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            AppLogger.sync.error(
                "Failed to encode activity payload: \(String(describing: error), privacy: .public)"
            )
            return
        }

        let context = modelContainer.mainContext
        let operation = PendingOperation(
            operationType: SyncOperationType.createActivity,
            circleId: activity.circle?.id,
            payloadJSON: payloadData
        )
        context.insert(operation)
        do {
            try context.save()
        } catch {
            AppLogger.sync.error(
                "Failed to persist pending op: \(String(describing: error), privacy: .public)"
            )
            return
        }

        refreshPendingCount()
        triggerDrain()
    }

    /// Public entrypoint: schedules a drain pass unless one is already
    /// running. Safe to call from app-foreground, sign-in completion,
    /// or a manual retry button.
    func triggerDrain() {
        guard inFlightDrain == nil else { return }
        inFlightDrain = Task { [weak self] in
            await self?.drainOnce()
            await MainActor.run {
                self?.inFlightDrain = nil
            }
        }
    }

    private enum ChunkOutcome {
        case sent
        case deferred(String)
        case failed(String)
    }

    private func drainOnce() async {
        guard await apiClient.tokenStore.currentTokens() != nil else {
            status = .offline
            return
        }

        let context = modelContainer.mainContext
        let pending = fetchPendingOperations(context: context)
        guard let pending else { return }

        guard !pending.isEmpty else {
            status = .idle
            lastError = nil
            pendingCount = 0
            return
        }

        status = .draining
        var sentAny = false

        for chunk in pending.chunked(into: Self.batchChunkSize) {
            switch await sendChunk(chunk, context: context) {
            case .sent:
                sentAny = true
            case let .deferred(message):
                status = .offline
                lastError = message
                return
            case let .failed(message):
                status = .error(message)
                lastError = message
                return
            }
        }

        if sentAny {
            lastSyncAt = .now
        }
        lastError = nil
        status = .idle
        refreshPendingCount()
    }

    private func fetchPendingOperations(context: ModelContext) -> [PendingOperation]? {
        let descriptor = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLogger.sync.error(
                "Failed to fetch pending ops: \(String(describing: error), privacy: .public)"
            )
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
            return nil
        }
    }

    private func sendChunk(
        _ chunk: [PendingOperation],
        context: ModelContext
    ) async -> ChunkOutcome {
        let bodyData: Data
        do {
            bodyData = try buildBatchBody(operations: chunk)
        } catch {
            AppLogger.sync.error(
                "Failed to assemble sync batch body: \(String(describing: error), privacy: .public)"
            )
            return .failed("Failed to assemble sync payload.")
        }

        do {
            let response: SyncBatchResponse = try await apiClient.sendRawJSON(
                method: .post,
                path: "/v1/sync/batch",
                body: bodyData
            )
            let acked = Set(response.acks.map(\.clientOpId))
            for op in chunk where acked.contains(op.clientOpId) {
                context.delete(op)
            }
            try context.save()
            AppLogger.sync.info(
                "Sync batch acked \(response.acks.count, privacy: .public) ops."
            )
            return .sent
        } catch let apiError as APIError {
            return handleAPIFailure(apiError, chunk: chunk, context: context)
        } catch {
            AppLogger.sync.error(
                "Save after sync ack failed: \(String(describing: error), privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    private func handleAPIFailure(
        _ error: APIError,
        chunk: [PendingOperation],
        context: ModelContext
    ) -> ChunkOutcome {
        let message = error.errorDescription ?? "Sync failed."
        if error.isAuthFailure {
            AppLogger.sync.notice("Sync deferred: \(message, privacy: .public)")
            return .deferred(message)
        }
        for op in chunk {
            op.attemptCount += 1
            op.lastAttemptAt = .now
            op.lastErrorMessage = message
        }
        try? context.save()
        AppLogger.sync.error("Sync batch failed: \(message, privacy: .public)")
        return .failed(message)
    }

    /// Builds the `POST /v1/sync/batch` body from durable queue rows.
    /// Each row's stored `payloadJSON` is re-parsed and embedded as the
    /// op's `payload` field so the wire format stays a homogeneous
    /// JSON document regardless of the underlying payload type.
    private func buildBatchBody(
        operations: [PendingOperation]
    ) throws
        -> Data
    {
        var wireOps: [[String: Any]] = []
        wireOps.reserveCapacity(operations.count)
        for op in operations {
            let parsedPayload: Any
            do {
                parsedPayload = try JSONSerialization.jsonObject(with: op.payloadJSON)
            } catch {
                parsedPayload = [String: Any]()
                AppLogger.sync.error(
                    "Discarding malformed payload for op \(op.clientOpId.uuidString, privacy: .public)"
                )
            }
            var dict: [String: Any] = [
                "clientOpId": op.clientOpId.uuidString.lowercased(),
                "operationType": op.operationType,
                "payload": parsedPayload,
            ]
            if let circleId = op.circleId {
                dict["circleId"] = circleId.uuidString.lowercased()
            }
            wireOps.append(dict)
        }
        let envelope: [String: Any] = ["operations": wireOps]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Array chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
