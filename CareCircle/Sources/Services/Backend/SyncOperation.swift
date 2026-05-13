import Foundation

// MARK: - SyncOperationType

/// Stable string identifiers used as `operationType` on `POST /v1/sync/batch`.
/// Backend mirrors the snake-case naming convention used by its sync tests.
enum SyncOperationType {
    static let createActivity = "create_activity"
}

// MARK: - CreateActivityPayload

/// JSON payload describing a newly composed activity that the iOS app
/// wrote to SwiftData/CloudKit. Mirrored to the backend so the same row
/// can be replayed by other platforms or a future read path.
///
/// Photo/audio attachments are intentionally omitted in this slice —
/// those require an upload-then-reference flow against MinIO and ship
/// in a later phase.
nonisolated struct CreateActivityPayload: Codable, Sendable, Equatable {
    let activityId: UUID
    let type: String
    let body: String
    let createdAt: Date
    let authorAppleUserID: String
    let authorDisplayName: String
    let audioDurationSeconds: Double
    let extractedEntitiesJSON: String?
}

// MARK: - Sync wire format

/// `POST /v1/sync/batch` response envelope.
nonisolated struct SyncBatchResponse: Decodable, Sendable {
    let acks: [Ack]

    nonisolated struct Ack: Decodable, Sendable, Equatable {
        let clientOpId: UUID
        let status: Status

        nonisolated enum Status: String, Decodable, Sendable {
            case queued
            case duplicate
        }
    }
}
