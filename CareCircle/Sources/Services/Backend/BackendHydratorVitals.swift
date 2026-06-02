import Foundation
import OSLog
import SwiftData

// MARK: - Vitals hydration (Phase 33)

extension BackendHydrator {
    private static let vitalsPageLimit = 50
    private static let vitalsMaxPages = 5

    func hydrateVitals(circleId: UUID, modelContext: ModelContext) async throws {
        guard localVitalsCount(in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Vitals skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        var cursor: String?
        var pageCount = 0
        var inserted = 0
        while pageCount < Self.vitalsMaxPages {
            let path = vitalsListPath(circleId: circleId, cursor: cursor)
            let response: VitalsResponse = try await apiClient.send(
                method: .get,
                path: path,
                authenticated: true
            )
            for dto in response.vitals {
                let vital = BackendHydratorMappers.makeVital(from: dto)
                vital.circle = circle
                modelContext.insert(vital)
                inserted += 1
            }
            cursor = response.nextCursor
            pageCount += 1
            if cursor == nil { break }
        }
        AppLogger.backend.info(
            "Hydrated \(inserted, privacy: .public) vitals over \(pageCount, privacy: .public) pages."
        )
    }

    private func localVitalsCount(in circleId: UUID, modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Vital>(
            predicate: #Predicate { $0.circle?.id == circleId }
        )
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            AppLogger.backend.error(
                "Local count fetch failed for Vital: \(String(describing: error), privacy: .public)"
            )
            return 1
        }
    }

    private func vitalsListPath(circleId: UUID, cursor: String?) -> String {
        let base = "/v1/circles/\(circleId.uuidString.lowercased())/vitals"
        var components = URLComponents()
        components.path = base
        var items = [URLQueryItem(name: "limit", value: "\(Self.vitalsPageLimit)")]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(base)\(query)"
    }
}
