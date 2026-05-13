# Phase 6 — AI entity extraction (Foundation Models, on-device)

**Goal (from build prompt):** Posted voice/text notes get structured entities pulled out — medications mentioned, vitals, appointments, meals, symptoms — and these surface as chips/cards on the activity row. iOS 26+ runs the extraction on-device through the `FoundationModels` framework using `LanguageModelSession` with a `@Generable` output type. Older devices show "Extraction not available on this device" gracefully.

Per spec §5.4: AI runs on-device first. The cloud fallback to gpt-4o-mini via a PHI-stripped proxy is *out of scope for v1 CloudKit-only* (the proxy backend doesn't exist; CLAUDE.md is explicit). The architecture is split behind a protocol so the cloud fallback can drop in during Phase 13+.

## Scope (do)

1. `ExtractedEntities` Codable value type holding optional arrays: `medications`, `vitals`, `appointments`, `meals`, `symptoms`, `generalNotes` and a `summary` string. Each child carries `name`, `details`, and `confidence` (low/medium/high).
2. `EntityExtractor` protocol with `extract(from text: String) async throws -> ExtractedEntities` plus `isAvailable: Bool`.
3. `FoundationModelsEntityExtractor` (iOS 26+) using `LanguageModelSession` and `@Generable` output. Prompt is short, deterministic, and operates only on the transcript/body text (no member identifiers). PHI redaction at the input stage replaces the Circle's care-recipient name with `[RECIPIENT]` before sending.
4. `UnavailableEntityExtractor` returns `isAvailable = false` and throws `EntityExtractionError.unavailable` so callers can show the disabled state.
5. Persistence: `Activity` gains `extractedEntitiesJSON: String?` (optional, default nil). Decoded on read via a computed `extractedEntities: ExtractedEntities?`.
6. Wiring: after a text or voice Activity is saved, fire an async extraction task. On success, JSON-encode and persist on the same Activity (modelContext save).
7. UI: `ExtractedEntitiesView` renders chips (medication chips with pill icon, vitals chips with heart icon, etc.). Lives below the body text in both row and detail. Loading state shows a small "Reading…" pill while extraction is in flight.
8. Disclaimer: every medication chip carries a tap-info that shows "Not medical advice — consult your healthcare provider." per spec §5.6.

## Out of scope

- Cloud fallback / PHI-stripping proxy — needs backend (Phase 13+).
- Editing extracted entities. They are read-only suggestions in v1.
- Acting on them (e.g. auto-creating Medications). That's Phase 7.

## Architecture

```
Sources/Services/Extraction/
  ExtractedEntities.swift             # Codable value types
  EntityExtractor.swift               # protocol + error enum
  EntityExtractorFactory.swift        # availability-based factory
  FoundationModelsEntityExtractor.swift  # iOS 26+ on-device
  UnavailableEntityExtractor.swift    # fallback for older OS
  PHIRedactor.swift                   # name redaction helper

Sources/Features/Activity/
  ExtractedEntitiesView.swift         # chip layout
  ActivityExtractionRunner.swift      # @Observable; kicks off + persists
```

The factory chooses `FoundationModelsEntityExtractor` if `#available(iOS 26.0, *)` AND `SystemLanguageModel.default.availability == .available`; otherwise `UnavailableEntityExtractor`.

## Wiring

- `ActivityComposerView.submit()` and `VoiceComposerView.submit()` schedule extraction after their `try modelContext.save()`. They don't block the dismiss.
- `ActivityExtractionRunner` holds the factory, takes an Activity ID, performs extraction off-main, then re-fetches the Activity and writes back the JSON in a transaction. Failures log and move on.

## Build sequence

1. Add Activity.extractedEntitiesJSON + computed accessor. Build.
2. Add Codable types + protocol + redactor + factory + fallback. Build.
3. Add FoundationModelsEntityExtractor with @Generable Codable struct mirror. Build (this may surface API issues; iOS 26 framework first-time use).
4. Add ExtractionRunner. Build.
5. Wire into composers. Build.
6. ExtractedEntitiesView; render in row + detail. Build.
7. swiftformat + swiftlint clean.
8. Commit + push.

## Risks

- **Foundation Models API surface** is iOS 26-fresh. If the `@Generable` macro path turns out to require additional setup, fall back to free-form JSON output parsed via `JSONDecoder` (still on-device). Stay on-device either way.
- **Latency**: extraction on a Pixel-class Neural Engine is ~1–3s for the small models. UI must accommodate this without blocking; runner already async.
- **Hallucinations**: with a short tightly-scoped prompt this stays low. Confidence scores are heuristic, set by the model — surface them as visual subtlety only.
- **Privacy logging**: never log decoded entity text (could be PHI). Logs use only category + count.

## DoD

- Saving a voice or text note triggers extraction within 200ms of save.
- Within 3s on iOS 26+, chips appear under the row.
- Activity persists the JSON so chips survive app relaunch.
- Older devices show no chips and no errors.
- Disclaimers present on medication chips.
- xcodebuild, swiftformat, swiftlint clean.

## Self-critique

- Persisting `extractedEntitiesJSON` as a string column duplicates parsing on every read; cached `extractedEntities` is good enough for v1 since rows are small.
- The runner re-fetches by ID rather than holding the Activity reference; this is required because the extraction runs off-main and SwiftData models are MainActor-bound.
- Doing extraction inline at post-time (not lazy) is the right product call: chips should appear within the natural feed dwell time, not on first row scroll.
