import Foundation

// MARK: - BackendInferenceClient

/// Thin typed wrapper over ``APIClient`` for the
/// `/v1/inference/extract` endpoint. Used by
/// ``CloudInferenceEntityExtractor`` on devices that cannot run the
/// on-device Foundation Models extractor.
///
/// The wrapper exists so the underlying network surface is mockable for
/// future tests and follows the codebase pattern set by
/// ``BackendDocumentService``, ``BackendAuthService`` and
/// ``BackendRealtimeClient``.
@Observable
final class BackendInferenceClient {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Posts a PHI-redacted transcript to the cloud extractor.
    ///
    /// The caller is responsible for redacting recipient + caregiver
    /// names with ``PHIRedactor`` before invoking this method; the
    /// backend never logs prompt content.
    func extract(
        redactedTranscript: String,
        locale: String? = nil
    ) async throws(APIError)
        -> ExtractedEntities
    {
        let request = InferenceExtractRequest(
            redactedTranscript: redactedTranscript,
            locale: locale
        )
        let response: InferenceExtractResponse = try await apiClient.send(
            method: .post,
            path: "/v1/inference/extract",
            body: request
        )
        return response.toExtractedEntities()
    }
}

// MARK: - Wire types

nonisolated private struct InferenceExtractRequest: Encodable, Sendable {
    let redactedTranscript: String
    let locale: String?
}

nonisolated private struct InferenceExtractResponse: Decodable, Sendable {
    let medications: [ExtractedEntity]
    let vitals: [ExtractedEntity]
    let appointments: [ExtractedEntity]
    let meals: [ExtractedEntity]
    let symptoms: [ExtractedEntity]
    let generalNotes: [ExtractedEntity]
    let summary: String?
    let model: String?

    func toExtractedEntities() -> ExtractedEntities {
        ExtractedEntities(
            medications: medications,
            vitals: vitals,
            appointments: appointments,
            meals: meals,
            symptoms: symptoms,
            generalNotes: generalNotes,
            summary: summary
        )
    }
}
