# Phase 30 — Voice handoff completion (cloud fallback + end-of-shift digest)

**Status:** in progress
**Started:** 2026-05-13

## What this is

Two-part completion of the voice-handoff feature surface (spec §4.3, §5.4):

**Part A — Cloud inference fallback (iOS < 26).** The on-device `FoundationModelsEntityExtractor` is iOS-26-only; everyone else currently gets `UnavailableEntityExtractor` (throws). Phase 30 adds a `CloudInferenceEntityExtractor` that POSTs the PHI-redacted transcript to a new backend route `/v1/inference/extract` and decodes the same `ExtractedEntities` shape. The factory selects on-device if available, cloud otherwise.

**Part B — End-of-shift digest.** A new domain (`ShiftDigest`) where the off-going caregiver records a 20–30s voice memo at end of shift. The system pre-aggregates structured artifacts from the shift window (dose events, appointments, journal entries when Phase 34 ships) and the caregiver narrates a summary over the top. The next caregiver opens the digest, sees the structured rollup + transcript + audio, reads in <60s.

## Why it matters

- **Cloud fallback:** Most TestFlight users will be on iOS 17/18/25 for the next ~6 months. Without it, the AI entity-extraction story is dark on every device that isn't running a developer beta. Closes spec §5.4's "cloud fallback via PHI-stripped proxy" promise.
- **End-of-shift digest:** Realizes the spec §4.3 voice-first promise. Today voice notes are atomic feed posts; the digest gives caregivers the "what should I know about the last 8 hours" view that families actually need at handoff.

---

## Part A — Cloud inference fallback

### End state

1. **New backend route** `POST /v1/inference/extract` accepting `{ redactedTranscript: string, locale?: string }` and returning the exact JSON shape of `ExtractedEntities`. Bearer-auth gated (existing middleware). Per-circle rate limit (30/hour, sliding window via Redis).
2. **New backend service** `services/inference.ts` wrapping OpenAI's chat completions with `gpt-4o-mini`, structured-output mode, system + user prompt mirroring the on-device prompt.
3. **Env config** for `OPENAI_API_KEY` (required when feature enabled), `OPENAI_MODEL` (default `gpt-4o-mini`), `INFERENCE_ENABLED` (kill switch).
4. **iOS** new file `CloudInferenceEntityExtractor.swift` conforming to `EntityExtractor`, calls APIClient `.post("/v1/inference/extract")`.
5. **iOS** factory selects on-device if `FoundationModelsEntityExtractor.isPlatformAvailable`, otherwise `CloudInferenceEntityExtractor`. Tests: factory selection on each version arm.
6. **Backend integration test** covers: 200 happy path (mocked OpenAI), 429 rate-limit, 503 when feature disabled, auth required.
7. PHI guarantee enforced: the route **does not log** the transcript content. Only `(userId, circleId, transcriptLength, durationMs, model)`.

### Files touched

```
backend/apps/api/src/config.ts                          # +OPENAI_* env keys
backend/apps/api/src/services/inference.ts              # NEW
backend/apps/api/src/routes/inference.ts                # NEW
backend/apps/api/src/app.ts                             # +inferenceRoutes register
backend/apps/api/test/inference.test.ts                 # NEW
packages/shared/src/schemas.ts                          # +inferenceExtractSchema + response type
CareCircle/Sources/Services/Extraction/
  CloudInferenceEntityExtractor.swift                   # NEW
  EntityExtractorFactory.swift                          # factory branch update
CareCircle/Sources/Services/Backend/
  BackendInferenceClient.swift                          # NEW (typed wrapper over APIClient)
```

### Architectural decisions

- **Why a separate `BackendInferenceClient.swift` and not inline in CloudInferenceEntityExtractor?** Keeps the network surface mockable for future tests and matches the codebase pattern (BackendDocumentService, BackendRealtimeClient, etc.).
- **Why OpenAI vs another provider?** Spec §5.4 specifies it. Switchable via env var so we can drop in Anthropic/Mistral later.
- **Why structured output (`response_format: json_schema`) instead of free-form prompting?** Eliminates a class of decode errors and matches the iOS `@Generable` schema-driven approach from FoundationModels.
- **Rate limiting:** 30 calls/circle/hour. At ~30¢/hr worst case (gpt-4o-mini @ ~$0.15/1M input + ~$0.60/1M output, 1500 tokens avg per call), this is the right per-user budget. Sliding window via existing Fastify rate-limit plugin (per-circle key via `keyGenerator`).
- **Idempotency:** Not needed. Extraction is read-only on the server side; client retry is safe.

### Risks

- **OPENAI_API_KEY rotates / runs out:** Route returns 502 with a clear error code. Client falls through to `UnavailableEntityExtractor` semantics (entity-extraction silently absent — voice note still posts).
- **Cost runaway:** Rate limit + per-circle keying caps it. If we see real abuse, a daily budget cap in Redis is a one-day follow-up.
- **PHI leakage via prompt:** Defended in depth — client-side `PHIRedactor.redact()` runs *before* the network call. Server never logs prompt content. Both safety nets are required.

---

## Part B — End-of-shift digest

### End state

1. **New SwiftData model** `ShiftDigest` (id, shiftStartAt, shiftEndAt, narratorAppleUserID, narratorDisplayName, audioData, audioDurationSeconds, transcript, summary, extractedEntitiesJSON, structuredArtifactsJSON, createdAt, circle).
2. **New backend table** `shift_digests` (encrypted transcript + summary + entities; audio stored via existing MinIO doc-key pipeline).
3. **New route** `POST/GET /v1/circles/:circleId/digests` following the activities pattern.
4. **New view** `ShiftDigestComposerView` — opens from Today / Activity feed "End shift" button:
   - Pulls structured artifacts within the active shift window (start = most-recent shift's `clockInAt` for this caregiver; end = now).
   - Pre-fills the artifacts panel: doses given/missed, appointments attended, journal entries (Phase 34), vitals (Phase 33).
   - Caregiver records 20-30s voice memo over the top.
   - Submit → save SwiftData → sync → extract entities → applicator delivers to other devices.
5. **New view** `ShiftDigestDetailView` — render structured artifacts + transcript + audio player + entity chips.
6. **New view** `ShiftDigestRow` for embedding in Activity feed.
7. **Realtime applicator** + **hydrator** updates following the codebase pattern.

### Files touched (Part B)

```
CareCircle/Sources/Models/ShiftDigest.swift                          # NEW
CareCircle/Sources/Features/Shifts/ShiftDigestComposerView.swift     # NEW
CareCircle/Sources/Features/Shifts/ShiftDigestDetailView.swift       # NEW
CareCircle/Sources/Features/Shifts/ShiftDigestRow.swift              # NEW
CareCircle/Sources/Features/Shifts/ShiftDigestService.swift          # NEW (artifact aggregation)
CareCircle/Sources/Services/Backend/
  BackendReadDTOs.swift                                              # +ShiftDigestDTO + Response
  BackendHydratorMappers.swift                                       # +makeShiftDigest/updateShiftDigest
  SyncEngine.swift                                                   # +enqueueShiftDigestCreate + payload
  BackendHydrator.swift                                              # +shift digest hydration call
  BackendRealtimeApplicatorsShiftDigest.swift                        # NEW (Phase 21/22 pattern)
CareCircle/Sources/App/SignedInRootView.swift or similar             # +environment plumbing if needed
backend/packages/db/migrations/0012_shift_digests.sql                # NEW table + RLS + notify trigger
backend/apps/api/src/routes/digests.ts                               # NEW
backend/apps/api/src/app.ts                                          # +digestRoutes register
backend/apps/api/test/digests.test.ts                                # NEW
packages/shared/src/schemas.ts                                       # +shiftDigest schemas
```

### Architectural decisions (Part B)

- **Why a new domain vs reusing Activity type?** Digests have a structured time-window field and the structured-artifacts JSON, which doesn't fit Activity's flat shape. Separate model also lets the digest detail view diverge from the activity row.
- **Audio storage:** Audio data inline on the `@Model` for now (matching VoiceComposerView's existing pattern); future migration to MinIO via BackendDocumentService is a Phase 35+ follow-up — out of scope here.
- **Artifact aggregation source of truth:** Aggregation runs on the client at compose time, snapshotted into `structuredArtifactsJSON`. We don't re-aggregate on read — the snapshot is the historical record of "what the caregiver narrated against."
- **Shift window detection:** Look for an active CareShift assigned to this caregiver (status `.active`). If none, default to "last 8 hours" with the caregiver able to manually adjust.

### Risks (Part B)

- **No active shift:** Graceful fallback to the 8-hour default; UI shows "(adjustable)" hint.
- **Empty shift (no activity in window):** Digest still allowed; caregiver may want to say "uneventful, all doses on time, mood good."
- **Audio + transcript size:** 90s of M4A audio is ~720KB; transcript ~500 chars. SwiftData externalStorage handles. Network upload is unchanged from existing voice-note plumbing.

---

## Quality gates (this phase)

1. `xcodebuild` clean.
2. `swiftformat --lint` clean on every touched iOS file.
3. `swiftlint` clean (file/type length thresholds).
4. `pnpm test` clean in `backend/` (including new inference + digests tests).
5. Simulator test (iOS 17.5 device — to verify cloud fallback path actually fires): boot sim → install build → sign in via mock-Apple-token flow if available, otherwise inspect via SwiftData store → trigger voice note → confirm extraction returns from cloud path → take screenshot.
6. Audit pass: re-read all new files with critic's eye, fix any missed accessibility labels, empty states, marketing words, force-unwraps.
7. Commit: `feat(ios+api): voice handoff cloud fallback + end-of-shift digest (Phase 30)`.

## Out of scope

- Migrating audio to MinIO (still inline on `@Model`).
- Bulk-export digests to PDF.
- Pulling appointment/dose markers into the digest *narration* automatically (we surface them as structured artifacts; the caregiver narrates).
- Daily summary (digest is per-shift, not per-day).

## Open follow-ups (Phase 30.1 candidates)

- Audio uploads via MinIO + presigned URL (mirrors BackendDocumentService).
- Cloud fallback warm-up: pre-flight `/v1/inference/health` from the client on cold-start to surface "AI unavailable" early.
- Cost dashboard for OpenAI usage.

## Definition of done

- [ ] Backend `/v1/inference/extract` route shipped with tests passing.
- [ ] iOS `CloudInferenceEntityExtractor` ships and the factory selects it on iOS < 26.
- [ ] Backend `shift_digests` table + migration + route + tests shipped.
- [ ] iOS `ShiftDigest` model + composer + detail + row + service + applicator + hydrator shipped.
- [ ] xcodebuild + swiftformat + swiftlint clean.
- [ ] Backend `pnpm test` clean.
- [ ] Simulator launch + functional verification screenshots captured.
- [ ] Audit pass committed alongside implementation if any fixes needed.
- [ ] Commit + push under conventional commit.
