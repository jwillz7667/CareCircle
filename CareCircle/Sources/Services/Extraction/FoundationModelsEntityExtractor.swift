import Foundation
import OSLog
#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - FoundationModelsEntityExtractor

#if canImport(FoundationModels)

    @available(iOS 26.0, *)
    struct FoundationModelsEntityExtractor: EntityExtractor {
        let redactor: PHIRedactor

        static var isPlatformAvailable: Bool {
            if #available(iOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
            return false
        }

        var isAvailable: Bool {
            Self.isPlatformAvailable
        }

        func extract(from text: String) async throws -> ExtractedEntities {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw EntityExtractionError.emptyInput }
            guard isAvailable else { throw EntityExtractionError.unavailable }

            let sanitized = redactor.redact(trimmed)
            let session = LanguageModelSession(instructions: Self.systemInstructions)

            do {
                let response = try await session.respond(
                    to: Self.userPrompt(for: sanitized),
                    generating: GeneratedEntities.self
                )
                return response.content.toExtractedEntities()
            } catch {
                AppLogger.app.error(
                    "Foundation Models extraction failed: \(String(describing: error), privacy: .public)"
                )
                throw EntityExtractionError.modelFailure(String(describing: error))
            }
        }

        // MARK: - Prompt

        private static let systemInstructions = """
        You extract structured care entities from a single caregiver note. \
        The note is about a senior whose name has been replaced with [RECIPIENT]. \
        Caregiver names appear as [CAREGIVER_n]. \
        Be conservative: only include items the note clearly mentions. \
        Do not invent doses, times, or providers. \
        If the note is small talk or unrelated to care, return empty arrays.
        """

        private static func userPrompt(for text: String) -> String {
            """
            Pull out the following from this caregiver note:
            - medications (name + dose/instructions if mentioned)
            - vitals (blood pressure, glucose, weight, temperature, oxygen, pulse)
            - appointments (provider/title + time if mentioned)
            - meals (what was eaten, how much)
            - symptoms (pain, mood, sleep, energy, falls)
            - generalNotes (anything else clinically relevant)
            Set confidence to high only when the note states the value verbatim.

            Note:
            \(text)
            """
        }
    }

    // MARK: - @Generable mirror

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedEntity: Equatable {
        @Guide(description: "Short label, e.g. 'Lisinopril', 'Blood pressure', 'Cardiologist visit'.")
        var name: String

        @Guide(description: "Supporting detail such as dose, value, or time; omit if not stated.")
        var details: String?

        @Guide(description: "How clearly the note states this. One of: low, medium, high.")
        var confidence: String

        func toExtractedEntity() -> ExtractedEntity {
            ExtractedEntity(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                details: details?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                confidence: ExtractionConfidence(rawValue: confidence.lowercased()) ?? .medium
            )
        }
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedEntities: Equatable {
        @Guide(description: "Medications the caregiver mentioned by name.")
        var medications: [GeneratedEntity]

        @Guide(description: "Numeric or descriptive vital signs reported in the note.")
        var vitals: [GeneratedEntity]

        @Guide(description: "Healthcare appointments or visits referenced in the note.")
        var appointments: [GeneratedEntity]

        @Guide(description: "Meals, snacks, or hydration the recipient consumed or refused.")
        var meals: [GeneratedEntity]

        @Guide(description: "Symptoms, mood, sleep, pain, or behaviors observed.")
        var symptoms: [GeneratedEntity]

        @Guide(description: "Other clinically relevant observations that do not fit another bucket.")
        var generalNotes: [GeneratedEntity]

        @Guide(description: "Optional one-sentence neutral summary of the note. 140 characters max.")
        var summary: String?

        func toExtractedEntities() -> ExtractedEntities {
            ExtractedEntities(
                medications: medications.map { $0.toExtractedEntity() },
                vitals: vitals.map { $0.toExtractedEntity() },
                appointments: appointments.map { $0.toExtractedEntity() },
                meals: meals.map { $0.toExtractedEntity() },
                symptoms: symptoms.map { $0.toExtractedEntity() },
                generalNotes: generalNotes.map { $0.toExtractedEntity() },
                summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            )
        }
    }

    // MARK: - String helper

    private extension String {
        var nonEmpty: String? {
            isEmpty ? nil : self
        }
    }

#endif
