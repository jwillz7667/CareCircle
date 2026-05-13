import Foundation
import OSLog
import SwiftData

// MARK: - ActivityExtractionService

/// Fires on-device entity extraction for a freshly-saved Activity and writes
/// the JSON back onto the same row. Operates main-actor end-to-end because
/// SwiftData models are MainActor-bound; the network-free FoundationModels
/// session yields the cooperative thread while inferring.
@MainActor
enum ActivityExtractionService {
    static func enqueue(
        activityID: UUID,
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
                    "Entity extraction skipped (\(String(describing: error), privacy: .public))"
                )
                return
            } catch {
                AppLogger.app.error(
                    "Entity extraction failed: \(String(describing: error), privacy: .public)"
                )
                return
            }

            guard !entities.isEmpty else { return }
            guard let json = entities.encodedJSON() else {
                AppLogger.app.error("Failed to encode ExtractedEntities to JSON.")
                return
            }

            persist(json: json, totalCount: entities.totalCount, for: activityID, in: modelContext)
        }
    }

    private static func persist(
        json: String,
        totalCount: Int,
        for activityID: UUID,
        in modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.id == activityID }
        )
        do {
            guard let activity = try modelContext.fetch(descriptor).first else {
                AppLogger.app.info("Activity disappeared before extraction landed.")
                return
            }
            activity.extractedEntitiesJSON = json
            try modelContext.save()
            AppLogger.app.info(
                "Stored \(totalCount, privacy: .public) extracted entities."
            )
        } catch {
            AppLogger.app.error(
                "Failed to persist extracted entities: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
