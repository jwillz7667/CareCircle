import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - EntityExtractorFactory

enum EntityExtractorFactory {
    /// Returns the best available extractor for the current device.
    ///
    /// On iOS 26+ when Foundation Models is downloaded, runs entity
    /// extraction on-device with zero network round-trip.
    ///
    /// Otherwise — and only if `inferenceClient` is supplied —
    /// falls back to the backend's PHI-stripped cloud extractor.
    ///
    /// When no cloud client is available, callers get
    /// ``UnavailableEntityExtractor`` which throws on use; the voice
    /// note still saves, the caller just doesn't get entity hints.
    static func makeDefault(
        redactor: PHIRedactor,
        inferenceClient: BackendInferenceClient? = nil
    )
        -> any EntityExtractor
    {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *), FoundationModelsEntityExtractor.isPlatformAvailable {
                return FoundationModelsEntityExtractor(redactor: redactor)
            }
        #endif
        if let client = inferenceClient {
            return CloudInferenceEntityExtractor(client: client, redactor: redactor)
        }
        return UnavailableEntityExtractor()
    }
}
