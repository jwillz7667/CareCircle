# Phase 19 — Eager backend blob prefetch on hydration

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 18 unlocked decrypt of backend-only document placeholders on
demand: when a member taps a row whose `ciphertext.isEmpty` and
`backendObjectKey != nil`, `DocumentDetailView.decryptIfNeeded` issues
a presigned-URL fetch, downloads ciphertext, and decrypts. That path
works but pays the latency on every open, blocks offline viewing, and
gives no UI feedback if the user is on a slow connection.

Phase 19 closes the loop. After hydration completes, the app eagerly
pulls ciphertext for every placeholder document, writes the encrypted
blob back into the local `Document` row (still under the per-circle
DEK), and turns the row into a fully-readable local copy. Detail-view
open is then a pure SwiftData read + in-memory decrypt — no network
hop, works offline, identical UX for owner-uploaded and backend-only
rows.

The prefetcher reuses `BackendDocumentService.downloadCiphertext` from
Phase 18. Nothing new on the backend side — same presign + GET MinIO
shape, just driven by a sweeper instead of a tap.

## End state (definition of done)

1. New prefetch path on `BackendDocumentRetrySweeper`:
   - `triggerPrefetch(modelContext:)` schedules a pass when one isn't
     already running (mirrors `triggerSweep`).
   - Underlying actor work finds every `Document` with
     `isBackendPlaceholder && deletedAt == nil`, downloads the
     ciphertext via `BackendDocumentService.downloadCiphertext`, and
     stores `ciphertext + nonce + tag` back on the row.
   - Failure on any single document is non-fatal: log + carry on.
     The next foreground sweep picks the row up again.
2. The DEK gate is respected: a circle whose local Keychain doesn't
   yet hold a DEK is skipped. The `CircleDocumentKeySyncService` pull
   path already runs before prefetch, so a freshly-accepted share has
   the DEK by the time prefetch fires.
3. Lifecycle wiring:
   - `RootView.maybeHydrateOnce` fires prefetch after the existing
     hydrator + sweeper kicks.
   - `RootView.onChange(scenePhase == .active)` also fires prefetch
     so a phone that woke from background catches up.
4. Telemetry on the sweeper:
   - `lastPrefetchAt: Date?`
   - `lastPrefetchError: String?`
   - `prefetchPendingCount: Int`
   - Read by `MoreView` debug surface (same shape as the upload
     sweeper metadata).
5. Stale placeholder cleanup: if `downloadCiphertext` returns a 404
   (`DownloadError.fetchFailed(status: 404)`) we know the backend
   row is gone — soft-delete the local placeholder so it stops
   re-queueing forever.

## Out of scope (deferred)

- `BGAppRefreshTask` registration. That needs an Info.plist key
  (`BGTaskSchedulerPermittedIdentifiers`) which must be added via
  Xcode's Info tab — picked up in a later phase tied to a UI session.
- Prefetch progress UI. The sweep is silent; the row badge in
  `DocumentRowView` already says "Backend only" until the prefetch
  flips it to readable. Per-row progress indicators are polish.
- DEK rotation on member removal. Tracked in the Phase 18 follow-ups,
  separate phase.
- Backend-side WebSocket fanout for real-time updates. Backend
  scaffolding (LISTEN/NOTIFY) is in place but no iOS client; same
  reason as BGTask — needs Xcode UI for new entitlements/info.

## Architecture

```
RootView.maybeHydrateOnce
  └─ hydrator.triggerHydrateAll       (Phase 16, unchanged)
  └─ documentSweeper.triggerSweep     (Phase 17, unchanged)
  └─ CircleDocumentKeySyncService.pullForAllCircles  (Phase 18)
  └─ documentSweeper.triggerPrefetch  ← NEW

BackendDocumentRetrySweeper.triggerPrefetch
  └─ inFlightPrefetch = Task { … }
       └─ fetchPlaceholders(modelContext:)
            └─ Document where backendObjectKey != nil && ciphertext.isEmpty
                                && deletedAt == nil && circle != nil
            └─ filter: DocumentKeyStore has key for circle.id
       └─ for each placeholder:
            └─ try await service.downloadCiphertext(documentId: row.id)
            └─ row.ciphertext = downloaded.ciphertext
               row.nonce = downloaded.nonce
               row.tag = downloaded.tag
               row.updatedAt = .now
            └─ if 404: row.deletedAt = .now
       └─ modelContext.save()
       └─ update lastPrefetchAt / lastPrefetchError / prefetchPendingCount
```

## Risks and decisions

- **Why write ciphertext back into SwiftData instead of caching the
  plaintext?** Because the CloudKit-mirrored row is the canonical
  store. A plaintext cache would be a second source of truth that the
  vault would have to manage. Writing the ciphertext back makes the
  row identical to an owner-uploaded one — no special case in
  `DocumentDetailView`, no cache eviction, and CloudKit can mirror it
  to the device's own private database for offline cross-launch use.
- **What about the DEK race after share-accept?** Prefetch tolerates
  a missing local DEK by filtering it out per-circle. Worst case the
  next foreground pass picks the row up after the DEK arrives via
  `CircleDocumentKeySyncService.pullIfMissing`. No retry storm.
- **What if MinIO bandwidth is constrained?** The sweep runs
  serially (one at a time) to avoid hammering MinIO and the presign
  endpoint. Parallel fanout is a Phase-20+ polish if measurements
  warrant it.
- **Soft-delete on 404 vs hard-delete:** soft-delete keeps the row
  out of the placeholder query while preserving an audit trail. If
  the user re-uploads the same blob, a new row is created.

## Definition of done checklist

- [ ] `BackendDocumentRetrySweeper` gains prefetch state +
      `triggerPrefetch(modelContext:)`.
- [ ] Underlying prefetch implementation:
      - filters placeholders
      - filters by available DEK
      - calls `downloadCiphertext` per row
      - writes ciphertext/nonce/tag back to SwiftData
      - soft-deletes on 404
      - logs per-row failures, doesn't stop the batch
- [ ] `RootView` wires prefetch into both `maybeHydrateOnce` and the
      `.active` scenePhase branch.
- [ ] xcodebuild + swiftformat + swiftlint clean.
- [ ] Commit + push.

## Open follow-ups (later)

- `BGAppRefreshTask` so prefetch runs without a foreground.
- WebSocket fanout for real-time activity / dose updates.
- DEK rotation when removing a member.
