import Foundation

// MARK: - EntityExtractionError

enum EntityExtractionError: Error, Sendable, Equatable {
    case unavailable
    case emptyInput
    case modelFailure(String)
    case decodingFailure
}

// MARK: - EntityExtractor

protocol EntityExtractor: Sendable {
    var isAvailable: Bool { get }
    func extract(from text: String) async throws -> ExtractedEntities
}
