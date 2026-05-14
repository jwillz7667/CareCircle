# Phase 24 — Snapshot-on-reconnect resync

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 23 closed the UPDATE / soft-delete gap *while the WebSocket is connected*. But the socket is not always connected: the receive loop tears down on transient network failures (5 / 15 / 30 / 60s backoff), and `RootView` calls `stop()` on background and `start()` on foreground. While the socket is down, the server still LISTENs and fans out, but this client has no subscriber — and every change frame emitted in that window is dropped on the floor.

When the socket reconnects, today's behavior is: receive subscribed → resume change handling from "now." Any mutation that landed during the gap waits for the next cold-start hydration pass. For a user who locked their phone for 20 minutes, came back, and saw the app reconnect, the realtime layer reports the wrong state until they background+foreground or restart.

Phase 24 fixes this. **On every reconnect, the client runs a "snapshot resync" pass that calls every list-shaped applicator across every subscribed circle, exactly as if each domain had emitted one synthetic change frame.** The applicators are already idempotent (Phase 23's upsert + soft-delete merge), so the snapshot pass is correct without per-domain customization.

## Why this matters

- A user who returns to a backgrounded app sees fresh state immediately. No "pull to refresh" gesture, no cold-restart wait.
- The realtime stack becomes self-healing across network blips. The visible latency of a missed change drops from "until next cold-start" to "≈ subscribe-frame + one round-trip per domain."
- It is the cheapest correctness fix in the realtime stack: zero backend changes, ~80 lines of iOS code, uses existing applicators end-to-end.

## End state (definition of done)

1. **`BackendRealtimeClient` gains a `snapshotResync(circleIds:modelContext:)` method.** Iterates the subscribed circle IDs and dispatches the eight list-shaped applicators in parallel via a `TaskGroup`. The per-row dose applicator is skipped — doses naturally re-cover via change frames (UPDATE / DELETE) plus the medication applicator's cascade.

2. **`handleMessage`'s `.subscribed` branch detects reconnect vs first-connect.** A new instance-level flag `hasPriorConnection` flips to `true` after the first subscribed frame. If it was already true when the next subscribed arrives, the call is a reconnect; the snapshot pass fires.

3. **`isResyncing` published as observable state.** Surfaces in the existing Debug/Connectivity UI (no new view layer needed). Cleared when the snapshot completes (success or failure).

4. **First-connect path stays untouched.** Cold-start hydration owns the initial fetch — running snapshotResync on first subscribe would duplicate work. The flag ensures the first subscribed frame is a no-op.

5. **Build + lint clean.**

## Architecture

```
handleMessage(.subscribed(circles)):
  wasReconnect = hasPriorConnection
  hasPriorConnection = true
  (existing state updates)
  if wasReconnect:
    Task { await self.snapshotResync(circleIds: circles, modelContext: modelContext) }

snapshotResync(circleIds, modelContext):
  isResyncing = true
  AppLogger.backend.info("Realtime: snapshot resync starting for N circle(s)")
  await withTaskGroup of Void.self:
    for circleId in circleIds:
      group.addTask: applyActivityChange(...)
      group.addTask: applyMedicationChange(...)
      group.addTask: applyAppointmentChange(...)
      group.addTask: applyMemberChange(...)
      group.addTask: applyEmergencyContactChange(...)
      group.addTask: applyDocumentChange(...)
      group.addTask: applySosChange(...)
      group.addTask: applyCareMinuteChange(...)
  isResyncing = false
  AppLogger.backend.info("Realtime: snapshot resync complete")
```

## Concurrency

The applicators are `@MainActor` instance methods. The `TaskGroup` runs child tasks that `await` into the main actor for SwiftData work; URLSession's network calls happen off-main and parallelize naturally. URLSession enforces `httpMaximumConnectionsPerHost = 6` by default, so a burst of 8 × N circles parallel GETs queues sanely at the transport layer.

We do not gate the snapshot by a semaphore. With typical N = 1–3 circles, the worst-case burst is 24 GETs, which is well within URLSession's pooled-connection budget.

## Idempotency and ordering

- Each applicator's upsert pass is already idempotent (Phase 23): running it twice within a few seconds is wasted CPU + bandwidth but cannot produce duplicate rows or lose data.
- If a regular `change` frame arrives mid-snapshot for one of the same domains, both runs converge on the same backend state. The `modelContext.save()` from each commits to SwiftData serially on the main actor; CloudKit's eventual consistency handles the rest.
- The snapshot does not block subsequent `change` frames — the receive loop continues consuming frames on its own task while the snapshot's child tasks run.

## Risks and decisions

- **No persisted cursor.** The simplest design refetches everything, not just "what changed since the last frame." Doing it the precise way would require either (a) a server-side `since=<timestamp>` query parameter on every list endpoint, or (b) a client-tracked last-seen-cursor per (circle, table) pair. The full refetch wastes some bandwidth but keeps the implementation minimal and the correctness bar high. Bandwidth-efficient cursors are a Phase 25+ candidate.

- **Snapshot does not retract notifications.** If iPhone B posts a local SOS notification mid-disconnect for an event that the user has since acknowledged on iPhone A, the snapshot will update the local row to canceled but won't pull the notification from the tray. Tray cleanup remains the Phase 23 follow-up.

- **Snapshot does not refetch doses.** The dose applicator is per-row (no list endpoint); we cannot enumerate "all doses for this circle" cheaply, and stale dose rows are usually corrected by the medication applicator's cascade delete or by the next user-driven dose mutation. If a dose changed status during disconnect and its parent medication didn't change, the local row stays stale until the next change frame for that row or the next cold-start. Acceptable for v1.

- **No retry on individual applicator failure.** Each applicator already has its own `logRefetchFailure` path; a single domain failing during snapshot logs and continues. The next change frame or next disconnect-reconnect cycle will eventually heal that domain.

- **First-connect detection lives in memory.** `hasPriorConnection` is a `Bool` on the instance, not persisted. A force-kill + relaunch starts fresh: cold-start hydration will run, and the next subscribed frame is treated as first-connect (no snapshot). That's correct — cold-start *is* the snapshot in that case.

## Out of scope (deferred follow-ups)

- **Server-supported `since=<timestamp>` query parameter** for delta-only snapshot. Reduces bandwidth on reconnects, especially for circles with thousands of activities. Backend + iOS work.
- **Per-(circle, table) cursor persistence** so a force-kill relaunch can resume without a full hydration.
- **Notification retraction** when snapshot picks up an SOS cancellation that was missed during disconnect.
- **Visibility of snapshot progress in the user-facing UI.** Today it surfaces only in the debug panel; a top-bar "syncing…" indicator is a polish-phase item.

## Definition of done checklist

- [x] `BackendRealtimeClient.hasPriorConnection` flag added; flipped by `.subscribed` handler.
- [x] `BackendRealtimeClient.isResyncing` observable property added.
- [x] `snapshotResync(circleIds:modelContext:)` method added in a new `BackendRealtimeSnapshot.swift` file to keep `BackendRealtimeClient.swift` under the file_length warning.
- [x] Reconnect detection wired in `handleMessage`'s subscribed branch.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 25+ candidates)

- Bandwidth-efficient delta-only resync via server `since=` parameter.
- Persistent per-(circle, table) cursors across app launches.
- Pull-to-refresh trigger that calls the same `snapshotResync` path.
- Tray cleanup for SOS notifications when the snapshot picks up a cancellation.
