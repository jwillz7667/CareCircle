import Foundation
import OSLog
import SwiftData

// MARK: - ShiftDigestExtractionService

/// Same MainActor-bound extraction pipeline `ActivityExtractionService`
/// uses, but writes the result back onto a `ShiftDigest` row. Kept as
/// a separate type so the activity flow and the digest flow can be
/// updated independently without one accidentally clobbering the other.
@MainActor
enum ShiftDigestExtractionService {
    static func enqueue(
        digestID: UUID,
        text: String,
        extractor: any EntityExtractor,
        in modelContext: ModelContext
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, extractor.isAvailable else { return }

        Task { @MainActor in
            let entities: ExtractedEntities
            do {
                entities = try await extractor.extract(from: trimmed)
            } catch is CancellationError {
                return
            } catch let error as EntityExtractionError {
                AppLogger.app.info(
                    "Digest extraction skipped (\(String(describing: error), privacy: .public))"
                )
                return
            } catch {
                AppLogger.app.error(
                    "Digest extraction failed: \(String(describing: error), privacy: .public)"
                )
                return
            }

            guard !entities.isEmpty else { return }
            guard let json = entities.encodedJSON() else {
                AppLogger.app.error("Failed to encode digest ExtractedEntities to JSON.")
                return
            }

            persist(json: json, totalCount: entities.totalCount, for: digestID, in: modelContext)
        }
    }

    private static func persist(
        json: String,
        totalCount: Int,
        for digestID: UUID,
        in modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<ShiftDigest>(
            predicate: #Predicate { $0.id == digestID }
        )
        do {
            guard let digest = try modelContext.fetch(descriptor).first else {
                AppLogger.app.info("Shift digest disappeared before extraction landed.")
                return
            }
            digest.extractedEntitiesJSON = json
            try modelContext.save()
            AppLogger.app.info(
                "Stored \(totalCount, privacy: .public) digest entities."
            )
        } catch {
            AppLogger.app.error(
                "Failed to persist digest extracted entities: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
