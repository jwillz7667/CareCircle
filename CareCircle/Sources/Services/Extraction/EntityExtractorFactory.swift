import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - EntityExtractorFactory

enum EntityExtractorFactory {
    /// Returns the best available extractor for the current device.
    /// Foundation Models is iOS 26+; older builds get the disabled stub.
    static func makeDefault(redactor: PHIRedactor) -> any EntityExtractor {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *), FoundationModelsEntityExtractor.isPlatformAvailable {
                return FoundationModelsEntityExtractor(redactor: redactor)
            }
        #endif
        return UnavailableEntityExtractor()
    }
}
