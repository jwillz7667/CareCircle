import Foundation
import OSLog

// MARK: - CloudInferenceEntityExtractor

/// Cloud-backed fallback used when Foundation Models is unavailable on
/// the current device (iOS < 26 or the system language model has not
/// finished downloading). PHI is redacted client-side via
/// ``PHIRedactor`` before any data leaves the device — the server never
/// sees recipient or caregiver names in plaintext.
struct CloudInferenceEntityExtractor: EntityExtractor {
    let client: BackendInferenceClient
    let redactor: PHIRedactor
    let locale: String?

    init(
        client: BackendInferenceClient,
        redactor: PHIRedactor,
        locale: String? = Locale.current.identifier
    ) {
        self.client = client
        self.redactor = redactor
        self.locale = locale
    }

    var isAvailable: Bool {
        true
    }

    func extract(from text: String) async throws -> ExtractedEntities {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EntityExtractionError.emptyInput }

        let sanitized = redactor.redact(trimmed)
        do {
            return try await client.extract(redactedTranscript: sanitized, locale: locale)
        } catch {
            let description = String(describing: error)
            AppLogger.backend.notice(
                "Cloud inference failed: \(description, privacy: .public)"
            )
            throw EntityExtractionError.modelFailure(description)
        }
    }
}
