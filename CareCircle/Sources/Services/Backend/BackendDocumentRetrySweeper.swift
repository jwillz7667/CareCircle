import Foundation
import OSLog
import SwiftData

// MARK: - BackendDocumentRetrySweeper

/// Finds local `Document` rows whose encrypted blob has not yet been
/// mirrored to MinIO (`backendObjectKey == nil`) and re-runs the
/// `BackendDocumentService` upload pipeline for each one. Invoked on
/// app foreground and after backend-session verification — the same
/// hooks that drive `BackendHydrator`.
///
/// Local-first save is the design contract: `AddDocumentView` already
/// commits the SwiftData row before the upload pipeline runs, and a
/// transient network failure must never bubble up to the user. The
/// sweeper closes that loop in the background.
@Observable
@MainActor
final class BackendDocumentRetrySweeper {
    private(set) var isRunning = false
    private(set) var lastRunAt: Date?
    private(set) var pendingCount = 0
    private(set) var lastError: String?

    private let service: BackendDocumentService
    private var inFlight: Task<Void, Never>?

    init(service: BackendDocumentService) {
        self.service = service
    }

    /// Schedules a sweep unless one is already running. Safe to call
    /// from `RootView.onAppear`, scene-phase active, or after backend
    /// session verification resolves.
    func triggerSweep(modelContext: ModelContext) {
        guard inFlight == nil else { return }
        inFlight = Task { [weak self] in
            await self?.sweep(modelContext: modelContext)
            await MainActor.run {
                self?.inFlight = nil
            }
        }
    }

    /// Re-counts the pending-upload backlog without doing any uploads.
    /// Useful for the MoreView debug surface.
    func refreshPendingCount(modelContext: ModelContext) {
        pendingCount = fetchPending(modelContext: modelContext).count
    }

    private func sweep(modelContext: ModelContext) async {
        isRunning = true
        defer { isRunning = false }

        let pending = fetchPending(modelContext: modelContext)
        pendingCount = pending.count
        guard !pending.isEmpty else {
            lastRunAt = .now
            lastError = nil
            return
        }

        var successCount = 0
        var lastFailure: String?

        for document in pending {
            guard let circleId = document.circle?.id else { continue }
            do {
                let objectKey = try await service.upload(
                    BackendDocumentService.UploadRequest(
                        documentId: document.id,
                        circleId: circleId,
                        title: document.title,
                        documentType: document.type.rawValue,
                        mimeType: document.mimeType,
                        sizeBytes: document.sizeBytes,
                        ciphertext: document.ciphertext,
                        nonce: document.nonce,
                        tag: document.tag,
                        issuedAt: document.issuedAt,
                        expiresAt: document.expiresAt,
                        visibilityRoles: document.visibilityRoles.map(\.rawValue),
                        filename: document.title
                    )
                )
                document.backendObjectKey = objectKey
                document.updatedAt = .now
                successCount += 1
            } catch {
                let message = error.errorDescription ?? "Upload failed"
                AppLogger.backend.error(
                    "Document upload retry failed for \(document.id.uuidString, privacy: .public): \(message, privacy: .public)"
                )
                lastFailure = message
            }
        }

        if successCount > 0 {
            do {
                try modelContext.save()
            } catch {
                AppLogger.backend.error(
                    "Failed to persist document upload acks: \(String(describing: error), privacy: .public)"
                )
                lastFailure = error.localizedDescription
            }
        }

        pendingCount = fetchPending(modelContext: modelContext).count
        lastRunAt = .now
        lastError = lastFailure
    }

    /// Returns documents that need a backend upload pass: ciphertext
    /// present, backend key absent, not soft-deleted, and attached to a
    /// circle (we never queue orphaned rows for upload).
    private func fetchPending(modelContext: ModelContext) -> [Document] {
        let descriptor = FetchDescriptor<Document>(
            sortBy: [SortDescriptor(\Document.createdAt)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { document in
                document.backendObjectKey == nil
                    && !document.ciphertext.isEmpty
                    && document.deletedAt == nil
                    && document.circle != nil
            }
        } catch {
            AppLogger.backend.error(
                "Failed to fetch pending document uploads: \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }
}
