# Master Plan — Phases 30 through 34

**Status:** in progress
**Started:** 2026-05-13

This document captures the cross-phase architecture for the five-feature buildout (voice handoff completion, smart insights, pill-identifier upgrades, HealthKit vitals, symptom & mood journal). Each individual phase document (`docs/phases/PHASE_30_PLAN.md` …) keeps its own scope tight; this is the connective tissue.

---

## Xcode-UI dependencies (read first)

The autonomous build can ship everything in Phases 30, 31, 32, and 34 without any Xcode-UI step. **Phase 33 has a single hard pause** because Apple does not allow enabling HealthKit via `Info.plist` alone — the entitlement must be added via Xcode's Signing & Capabilities tab. The phase is structured so that **all HealthKit code is shipped, fully wired and behind a feature flag**, and the user only needs to:

1. Open `CareCircle.xcodeproj` in Xcode.
2. Select the `CareCircle` target.
3. Signing & Capabilities → `+ Capability` → **HealthKit**. Leave the default categories (no clinical-records toggle needed for v1).
4. (No further action; entitlements file + Info.plist usage descriptions are written by Phase 33.)

After the toggle, the HealthKit read path activates automatically on next launch. Manual-entry vitals work regardless.

---

## Architectural decisions shared across phases

### 1. The "new domain" template (codified)

Every new SwiftData-backed domain in this codebase follows the same six-file pattern. Phase 30's `ShiftDigest`, Phase 31's `Insight`, Phase 33's `Vital`, and Phase 34's `JournalEntry` all conform to this template:

```
Sources/Models/<Domain>.swift                   // @Model + enum kindRaw + circle back-ref
Sources/Features/<Domain>/                      // Composer / List / Detail / Row views
Sources/Services/<Domain>Service.swift          // pure-logic helpers (grouping, windowing, etc.)
+ amendments to:
Sources/Services/Backend/BackendReadDTOs.swift           // <Domain>DTO + <Domain>Response
Sources/Services/Backend/BackendHydratorMappers.swift    // make<Domain>(from:) + update<Domain>(_:from:)
Sources/Services/Backend/SyncEngine.swift                // Create<Domain>Payload + enqueue<Domain>Create
+ a new file for the applicator extension (mirrors Phase21/22 split):
Sources/Services/Backend/BackendRealtimeApplicators<Domain>.swift
+ amendments to:
Sources/Services/Backend/BackendHydrator.swift           // domain fetch + insert during cold-start
backend/packages/db/migrations/00XX_<domain>.sql         // table + indexes + RLS + notify trigger
backend/apps/api/src/routes/<domain>.ts                  // GET list + GET by id + POST + idempotency
```

Models live in `CareCircle/Sources/Models/` (not nested under `Features/`) because they're consumed by multiple feature folders + services. This matches the existing layout (`Activity.swift`, `Medication.swift`, `DoseEvent.swift`).

### 2. Cloud inference fallback (Phase 30 detail)

The on-device FoundationModels extractor only works on iOS 26+. iOS 17–25 devices today get an `UnavailableEntityExtractor` that throws. Phase 30 adds a thin backend proxy so those devices get the same extraction experience.

Boundary:

```
iOS (any version)
  └── ActivityExtractionService.enqueue(transcript, recipient, caregivers)
        └── PHIRedactor.redact(transcript, recipient, caregivers) -> RedactedTranscript
              (always client-side; PHI never leaves device)
        └── EntityExtractorFactory.makeDefault()
              ├── iOS 26+  -> FoundationModelsEntityExtractor (on-device)
              └── iOS < 26 -> CloudInferenceEntityExtractor (NEW)
                                └── POST /v1/inference/extract (redacted transcript only)
```

Backend contract:

- `POST /v1/inference/extract`
- Auth: bearer JWT (existing middleware)
- Rate limit: 30 calls per circle per hour (sliding window; existing rate-limit middleware)
- Request: `{ redactedTranscript: string, locale?: string }`
- Response: `{ medications: ExtractedEntity[], vitals: …, appointments: …, meals: …, symptoms: …, generalNotes: …, summary: string }` — **same JSON shape as the on-device extractor's output**, so client-side decoding is identical.
- Provider: OpenAI `gpt-4o-mini` (per spec §5.4); model name in env var, not hardcoded.
- Logging: log request size + duration + provider model; **never log transcript content**. Audit log captures `(userId, circleId, transcriptLength, durationMs)`.
- Cost discipline: 30-call rate limit caps a circle at ~$0.30/hour worst case at current pricing.

Both extractors implement the same `EntityExtractor` protocol; the factory's iOS-version branch is the only switch.

### 3. Smart insights engine (Phase 31 detail)

Insights are *derived facts* — fully reconstructible from existing data. We persist them as `@Model Insight` only to remember dismissals and to drive the unread-count badge.

```
Insight {
  id: UUID
  kindRaw: String         // .doseTimingDrift | .missedDoseRisk | .moodTrend | .vitalOutOfRange | .sleepDecline
  severityRaw: String     // .info | .suggestion | .warning
  subjectKind: String     // "medication" | "careRecipient" | "vital"
  subjectId: UUID?        // the specific medication / recipient / vital this is about
  title: String
  body: String
  computedAt: Date
  dismissedAt: Date?
  appliedAt: Date?        // for "Move reminder earlier?" type insights with a CTA
  circle: Circle?
}
```

Recompute trigger: `InsightsEngine.recompute(modelContext:)` is called from:
1. App foreground (scenePhase → .active) in RootView.
2. After any DoseEvent insert/update (debounced 5s).
3. After any JournalEntry insert (Phase 34, debounced 5s).

Recompute is idempotent — it scans existing data, derives the current set of insights, then upserts: any existing Insight whose `dismissedAt` is set is left alone; new ones are inserted; stale ones (subject no longer triggers the pattern) are soft-deleted by setting `appliedAt` to now.

No backend state for insights. Per-device, by design — different caregivers may find different insights relevant.

### 4. The "voice digest" vs "smart insight" distinction

These two are easy to conflate but serve different jobs:

- **Voice digest (Phase 30)** is a *human-authored* summary of one shift — what the off-going caregiver did, mood notes, what's queued for the next shift. The system aggregates structured artifacts (dose events, vitals, journal entries) and the caregiver narrates over the top in 20–30 seconds.
- **Smart insight (Phase 31)** is a *system-authored* observation across many shifts — "evening doses late 3× this week." No human input; on-screen as a card the user can dismiss or apply.

They share NO model or storage layer.

### 5. Per-domain notify trigger reuse

Migration `0010_notify_triggers.sql` already attaches `notify_circle_change()` to every existing PHI table. Each new domain in Phases 30–34 follows the same line:

```sql
CREATE TRIGGER notify_<domain> AFTER INSERT OR UPDATE OR DELETE ON <table>
  FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
```

The function pulls `circle_id` from `NEW.circle_id` (or `OLD.circle_id` for DELETE). Every new domain table includes `circle_id UUID NOT NULL REFERENCES circles(id)` for this reason.

### 6. Realtime applicator pattern (Phase 23 codified)

Applicators follow the Phase 23 upsert + soft-delete pattern: list-based domains refetch a window and reconcile against local; per-row-fetch domains (doses, sos) refetch one row and apply update-or-insert. No new pattern in Phases 30–34. New domains:

| Domain | Phase | Fetch shape |
|---|---|---|
| ShiftDigest | 30 | list, paginated 20 |
| Insight | 31 | *no realtime — local-only* |
| Vital | 33 | list, paginated 50 |
| JournalEntry | 34 | list, paginated 50 |

---

## Sequencing rationale

The phases are sequenced so each unlocks the next:

```
30 (voice digest + cloud fallback) → independent
31 (insights engine)                ─┐
32 (pill barcode + interactions)    │ both build on existing meds/dose data
                                    │
33 (vitals)                         ─┴─> feeds insights (vital-out-of-range pattern)
34 (journal)                        ────> feeds insights (mood-trend, sleep-decline patterns)
```

After Phase 34, a small Phase 35 follow-up extends the InsightsEngine with the new vital + journal patterns. That's noted but not committed-to here.

---

## Quality gates (every phase)

1. `xcodebuild -project CareCircle.xcodeproj -scheme CareCircle -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build` clean.
2. `swiftformat --lint` clean on every touched file.
3. `swiftlint` clean on every touched file (file_length 400 warn / 600 err, type_body_length 250 warn / 400 err).
4. For backend changes: `pnpm test` clean in `backend/`.
5. **Simulator functional test** for each phase: launch the app, exercise the new flow end-to-end, capture screenshots, verify state in the SwiftData store. Honest acknowledgement: without UI tests (forbidden until user approves), "fully tested" means *manually verified in simulator* — code-level correctness via build + lint + visual + state inspection. Said plainly in each phase's DOD.
6. Audit pass: after the initial implementation, re-read every new file with a critic's eye (one-pass code review) before commit. Catch: missing accessibility labels, missed empty states, missing error handling, missing pull-to-refresh, unused imports, marketing words in copy, force-unwraps.
7. Commit with `feat(ios): <one-line> (Phase NN)` or `feat(ios+api): <one-line> (Phase NN)` for cross-stack phases.

---

## Hard rules (carried from CLAUDE.md)

- No `project.pbxproj` edits.
- No UI tests until user approves.
- No force-unwraps in production.
- No singletons in production paths (DI via initializers / `@Environment`).
- No marketing words ("elegant," "robust," "beautiful").
- No AI attribution in commit messages.
- No HIPAA-compliance claims in user-facing copy.
- Triple-slash docs only on public API; no noise comments.
- SourceKit phantom diagnostics ignored — xcodebuild is truth.

---

## Open questions deferred to the user

None block the work. The HealthKit Xcode-capability step is the only user action required, and it can be done at any time before Phase 33 ships its functional simulator test. If the user is unavailable when Phase 33 reaches that gate, the phase ships with manual-entry + HK code merged-but-inactive and a clearly-marked TODO in the phase plan; Phase 34 continues unblocked.
