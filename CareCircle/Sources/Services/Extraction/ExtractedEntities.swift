import Foundation

// MARK: - ExtractionConfidence

nonisolated enum ExtractionConfidence: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

// MARK: - ExtractedEntity

nonisolated struct ExtractedEntity: Codable, Sendable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var details: String?
    var confidence: ExtractionConfidence

    init(
        id: UUID = UUID(),
        name: String,
        details: String? = nil,
        confidence: ExtractionConfidence = .medium
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.confidence = confidence
    }
}

// MARK: - ExtractedEntities

nonisolated struct ExtractedEntities: Codable, Sendable, Equatable {
    var medications: [ExtractedEntity] = []
    var vitals: [ExtractedEntity] = []
    var appointments: [ExtractedEntity] = []
    var meals: [ExtractedEntity] = []
    var symptoms: [ExtractedEntity] = []
    var generalNotes: [ExtractedEntity] = []
    var summary: String?

    var isEmpty: Bool {
        medications.isEmpty
            && vitals.isEmpty
            && appointments.isEmpty
            && meals.isEmpty
            && symptoms.isEmpty
            && generalNotes.isEmpty
            && (summary?.isEmpty ?? true)
    }

    var totalCount: Int {
        medications.count
            + vitals.count
            + appointments.count
            + meals.count
            + symptoms.count
            + generalNotes.count
    }

    func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
