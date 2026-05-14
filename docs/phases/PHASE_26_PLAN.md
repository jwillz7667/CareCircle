# Phase 26 — Cold-start SOS notification retraction

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 25 retracts SOS notifications when a cancellation arrives **through the realtime stack**. The path is: realtime applicator detects `wasActive → canceled` transition during `mergeSOSEvents`, then calls `removeDeliveredNotifications` + `removePendingNotificationRequests` for the offending identifier(s). Phase 24's snapshot resync extends that coverage across mid-session disconnects: when the WebSocket drops and reconnects, the snapshot pass calls every applicator including `applySosChange`, so cancellations that landed while disconnected get reconciled.

The remaining gap: **force-kill + relaunch**. If iPhone B posted the SOS notification *before* it was force-killed, then the SOS was canceled while B was dead, then B re-launches — neither path catches the retraction.

- Cold-start hydration (Phase 16) skips SOS when the local store already has rows. The user's old SOS rows survive the kill (SwiftData is on disk), so the hydrator never refetches.
- Realtime snapshot resync (Phase 24) only fires on *re*connect — a fresh launch's first subscribed frame is treated as first-connect, no snapshot.

The result: the stale notification sits in the tray until something else (a new realtime change frame, the user manually clearing it, or another disconnect-reconnect cycle) eventually retracts it. For a caregiver who locked their phone during a real SOS, the loud notification can persist for hours.

Phase 26 closes this. **The cold-start hydrator's SOS step is replaced with a reconcile pass that always fetches and merges, regardless of whether the local store is empty.** Cancellation transitions detected during the merge retract the corresponding notifications using the same identifier shape as Phase 22's post and Phase 25's realtime retract. The empty-local case still works the same — every DTO falls into the insert branch.

## Why this matters

- Closes the last "stale loud notification" hole in the SOS pipeline. Combined with Phase 22 (post), Phase 25 (realtime retract), and Phase 24 (snapshot resync), every code path that can flip an SOS to canceled now also clears its notification.
- Cold-start is the right place to do the catch-up: it's the one path that runs after a force-kill, before any user-visible UI renders, and it already touches every backend domain.
- Negligible cost. SOS is a low-volume domain (a typical Circle sees zero or one SOS per week), so the always-fetch behavior costs ~1 extra GET per circle per launch. The eight other domains keep their empty-store gate.

## End state (definition of done)

1. **`BackendHydrator.reconcileSOSEvents(circleId:modelContext:)` replaces `hydrateSOSEvents`.** Always runs (no empty-store gate). For each DTO with a matching local row, snapshots `wasActive`, runs `updateSOSEvent`, and appends the notification identifier when the row transitions to canceled. For each DTO without a local match, inserts.

2. **Save + retract.** After the per-circle save in `hydrate(circleId:...)`, retract any notifications collected by `reconcileSOSEvents`. Retraction uses the same `BackendRealtimeClient.sosNotificationID(for:)` helper introduced in Phase 25, so identifier shape stays in one place.

3. **No re-retraction.** Once a local row's `canceledAt` is non-nil, the `wasActive` snapshot taken on the next hydration sees the row as already-canceled, so the transition does not re-fire. Same invariant as the realtime applicator.

4. **No notification posting during cold-start.** The hydrator deliberately doesn't post for new SOS events it discovers — those rows could be days old, and announcing them on launch would be loud and surprising. This matches the prior hydrator behavior (silent inserts).

5. **Other domains untouched.** Only the SOS path drops the empty-store gate. Activities, medications, etc. keep their first-launch-only semantics because they have CloudKit as their authoritative replication path; SOS does not (it's backend-fanout only per Phase 22).

6. **Build + lint clean.**

## Architecture

```
hydrate(circleId, modelContext):
  try await hydrateActivities(...)          // unchanged
  try await hydrateMedications(...)         // unchanged
  …
  let retractIDs = try await reconcileSOSEvents(circleId, modelContext)   // NEW
  try await hydrateDocuments(...)           // unchanged

  try modelContext.save()
  retractStaleSOSNotifications(retractIDs)  // NEW

reconcileSOSEvents(circleId, modelContext):
  guard let circle = fetchCircle(...)
  let response = GET /v1/circles/<id>/sos
  let localMap = fetchLocalSOSMap(circleId, modelContext)
  var retractIDs: [String] = []
  for dto in response.events:
    if let existing = localMap[dtoID]:
      let wasActive = existing.canceledAt == nil
      let nowCanceled = dto.canceledAt != nil
      BackendHydratorMappers.updateSOSEvent(existing, from: dto, displayName: nil)
      if wasActive && nowCanceled:
        retractIDs.append(BackendRealtimeClient.sosNotificationID(for: existing.id))
    else:
      let event = makeSOSEvent(from: dto)
      event.circle = circle
      modelContext.insert(event)
  return retractIDs
```

## Identifier shape

The Phase 22 post site and Phase 25 retract site both go through `BackendRealtimeClient.sosNotificationID(for:)`. Phase 26 reuses the same helper so all three sources are in lock-step — if the format ever changes (e.g. namespacing by circle), one edit propagates.

## Risks and decisions

- **What if the local SOS store is empty on cold-start?** The reconcile loop runs but every DTO falls into the insert branch. `retractIDs` stays empty. No regression vs. the prior `hydrateSOSEvents` behavior.

- **What if the notification was never posted on this device?** `removeDeliveredNotifications` is a no-op for unknown identifiers. Same for `removePendingNotificationRequests`. No defensive checks needed — same property Phase 25 relies on.

- **What if the cancellation landed in the same launch session via realtime?** Phase 25's realtime applicator already retracted the notification. The local row's `canceledAt` is set, so on the next cold-start, the reconcile sees `wasActive = false` and skips. No double-retract.

- **CloudKit clobber concerns.** SOS does *not* replicate via CloudKit's `CKShare` — Phase 22 made it a backend-fanout flow. So always-fetch + reconcile cannot stomp on CloudKit state, because there is no CloudKit state for SOS. The same is *not* true for activities/medications/documents, which is why their empty-store gate stays.

- **Save granularity.** The per-circle save in `hydrate(circleId:)` already commits all hydrated rows. Retraction runs after save returns, so a save failure short-circuits the retract — that's correct (if the local row didn't commit as canceled, we don't want to retract a notification whose corresponding row still shows active).

- **Display name on insert.** The realtime applicator looks up member display names because it posts a notification. Cold-start does not post, so the insert path leaves `triggeredByDisplayName = ""` (matches prior hydrator behavior). The SOS list UI handles empty display name with a generic "Someone" fallback.

- **Reading `BackendRealtimeClient.sosNotificationID` from `BackendHydrator`.** The helper is `static` and module-internal, so any file in the app target can call it. No new module dependencies.

## Out of scope (deferred follow-ups)

- **Same treatment for dose / appointment / medication-missed escalation notifications** once those flows ship. Each will need its own reconcile + retract pass on cold-start.
- **Generic notification-retraction infrastructure.** The retract code path lives in two places now (realtime + cold-start). When a third arrives (e.g. notification posted by `BackendDocumentRetrySweeper`), it's worth extracting into a shared helper. Not in scope here.
- **Tray sweep for orphaned identifiers.** A device that has an `sos.event.<X>` notification in its tray but no corresponding local row (e.g. the local row was force-deleted) won't be retracted by this path. Acceptable — orphan rows shouldn't happen in practice.

## Definition of done checklist

- [x] `BackendHydrator.reconcileSOSEvents(circleId:modelContext:)` added (replaces `hydrateSOSEvents`).
- [x] `hydrate(circleId:)` calls the new method and threads the returned identifier list through to a post-save retract step.
- [x] Retract step calls `removeDeliveredNotifications` + `removePendingNotificationRequests` using identifiers from `BackendRealtimeClient.sosNotificationID(for:)`.
- [x] SOS reconcile + retract live in a new `BackendHydratorSOSReconcile.swift` extension file to keep `BackendHydrator.swift` under the file_length warning.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean (pre-existing `type_body_length` on `BackendHydrator` reduced 327 → 311 lines but still over threshold; not introduced here).
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 27+ candidates)

- Pull-to-refresh wiring that calls the realtime snapshot resync path on demand.
- Circles-table applicator (rename / owner-change) — requires a new `notify_circles` backend trigger.
- Generic notification-retraction helper used by all notification-posting flows.
