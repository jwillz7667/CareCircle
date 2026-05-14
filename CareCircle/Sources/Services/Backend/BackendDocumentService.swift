import Foundation
import OSLog

// MARK: - BackendDocumentService

/// Orchestrates the three-step encrypted-document upload pipeline to the
/// Railway backend:
///
///   1. `POST /v1/circles/:id/documents/upload-url` — backend mints a
///      presigned PUT URL against the `cc-documents` MinIO bucket.
///   2. `PUT <presigned url>` — raw ciphertext bytes; no auth header
///      (the URL carries the signature), `Content-Type` matches the
///      request so MinIO records it.
///   3. `POST /v1/circles/:id/documents` — metadata row with
///      `objectKey`, base64-encoded nonce + tag, and the rest of the
///      Document column set.
///
/// Steps 1 and 3 reuse `APIClient`'s bearer-token plumbing (including
/// the 401 → refresh retry); step 2 hits MinIO directly via
/// `URLSession` so the presign signature isn't double-encrypted.
///
/// All three steps fit inside the presign's 300 s TTL because we don't
/// persist the URL — if the network drops between steps the caller
/// (`AddDocumentView` or `BackendDocumentRetrySweeper`) catches the
/// thrown error and the document stays in its pre-upload state
/// (`backendObjectKey == nil`) for the next sweeper pass.
actor BackendDocumentService {
    /// Bucket name dedicated to encrypted document blobs; matches the
    /// backend enum in `uploadUrlSchema`.
    private static let documentsBucket = "cc-documents"

    private let apiClient: APIClient
    private let urlSession: URLSession

    init(
        apiClient: APIClient,
        urlSession: URLSession = .shared
    ) {
        self.apiClient = apiClient
        self.urlSession = urlSession
    }

    enum UploadError: LocalizedError, Sendable {
        case invalidPresignURL
        case presignFailed(String)
        case putFailed(status: Int?)
        case createMetadataFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPresignURL:
                "Backend returned an unusable upload URL."
            case let .presignFailed(message):
                "Couldn't reserve a backend upload slot: \(message)"
            case let .putFailed(status):
                if let status {
                    "Document upload rejected by storage (HTTP \(status))."
                } else {
                    "Document upload to storage failed."
                }
            case let .createMetadataFailed(message):
                "Document uploaded but metadata save failed: \(message)"
            }
        }
    }

    /// Owner-side input. Plaintext never leaves the caller — only the
    /// already-sealed ciphertext + nonce + tag travel here.
    struct UploadRequest: Sendable {
        let documentId: UUID
        let circleId: UUID
        let title: String
        let documentType: String
        let mimeType: String
        let sizeBytes: Int
        let ciphertext: Data
        let nonce: Data
        let tag: Data
        let issuedAt: Date?
        let expiresAt: Date?
        let visibilityRoles: [String]
        let filename: String?
    }

    /// Runs the full pipeline. Returns the `objectKey` the backend
    /// minted so the caller can persist it on the local `Document`.
    @discardableResult
    func upload(_ request: UploadRequest) async throws(UploadError) -> String {
        let presign = try await requestPresign(
            circleId: request.circleId,
            mimeType: request.mimeType,
            sizeBytes: request.sizeBytes,
            filename: request.filename
        )

        try await uploadCiphertext(
            to: presign.url,
            mimeType: request.mimeType,
            data: request.ciphertext
        )

        try await postMetadata(request: request, objectKey: presign.objectKey)

        AppLogger.backend.info(
            "Document \(request.documentId.uuidString, privacy: .public) uploaded as \(presign.objectKey, privacy: .public)"
        )
        return presign.objectKey
    }

    // MARK: Step 1 — presign

    private struct UploadURLRequest: Encodable, Sendable {
        let bucket: String
        let contentType: String
        let sizeBytes: Int
        let filename: String?
    }

    private func requestPresign(
        circleId: UUID,
        mimeType: String,
        sizeBytes: Int,
        filename: String?
    ) async throws(UploadError)
        -> DocumentUploadURLResponse
    {
        let body = UploadURLRequest(
            bucket: Self.documentsBucket,
            contentType: mimeType,
            sizeBytes: sizeBytes,
            filename: filename
        )
        do {
            return try await apiClient.send(
                method: .post,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/documents/upload-url",
                body: body
            )
        } catch {
            throw .presignFailed(error.errorDescription ?? "Presign failed")
        }
    }

    // MARK: Step 2 — PUT ciphertext

    private func uploadCiphertext(
        to urlString: String,
        mimeType: String,
        data: Data
    ) async throws(UploadError) {
        guard let url = URL(string: urlString) else {
            throw .invalidPresignURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await urlSession.upload(for: request, from: data)
        } catch {
            AppLogger.backend.error(
                "Presigned PUT failed: \(String(describing: error), privacy: .public)"
            )
            throw .putFailed(status: nil)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .putFailed(status: nil)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw .putFailed(status: httpResponse.statusCode)
        }
    }

    // MARK: Step 3 — POST metadata

    private struct CreateDocumentRequest: Encodable, Sendable {
        let title: String
        let documentType: String
        let objectKey: String
        let mimeType: String
        let sizeBytes: Int
        let encryptionNonce: String
        let encryptionTag: String
        let issuedAt: String?
        let expiresAt: String?
        let visibility: [String]?
    }

    private func postMetadata(
        request: UploadRequest,
        objectKey: String
    ) async throws(UploadError) {
        let body = CreateDocumentRequest(
            title: request.title,
            documentType: request.documentType,
            objectKey: objectKey,
            mimeType: request.mimeType,
            sizeBytes: request.sizeBytes,
            encryptionNonce: request.nonce.base64EncodedString(),
            encryptionTag: request.tag.base64EncodedString(),
            issuedAt: BackendDocumentService.formatShortDate(request.issuedAt),
            expiresAt: BackendDocumentService.formatShortDate(request.expiresAt),
            visibility: request.visibilityRoles.isEmpty ? nil : request.visibilityRoles
        )
        do {
            let _: DocumentCreateResponse = try await apiClient.send(
                method: .post,
                path: "/v1/circles/\(request.circleId.uuidString.lowercased())/documents",
                body: body
            )
        } catch {
            throw .createMetadataFailed(error.errorDescription ?? "Create metadata failed")
        }
    }

    // MARK: - Helpers

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated static func formatShortDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return shortDateFormatter.string(from: date)
    }
}
