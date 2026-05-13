import Foundation

// MARK: - UnavailableEntityExtractor

/// Fallback used when on-device extraction is unsupported (iOS < 26 or
/// the system language model is downloading / unsupported on the device).
struct UnavailableEntityExtractor: EntityExtractor {
    let isAvailable = false

    func extract(from _: String) async throws -> ExtractedEntities {
        throw EntityExtractionError.unavailable
    }
}
