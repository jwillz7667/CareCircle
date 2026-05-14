# Phase 27 — Pull-to-refresh wiring for snapshot resync

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 24's snapshot resync fans out all eight list-shaped applicators across every subscribed circle in parallel, and is currently triggered only by a WebSocket reconnect. That covers gaps from transient network blips and background→foreground transitions, but leaves the user with no explicit way to ask the app "go fetch the latest right now." On a flaky network, or when a member just pushed a change that the realtime layer hasn't fanned out yet, the user has no recourse beyond force-closing and relaunching.

Phase 27 wires `.refreshable {}` into the four primary content list views so a pull-down gesture calls `BackendRealtimeClient.snapshotResync(circleIds:modelContext:)` for the currently-displayed circle. Because the snapshot covers every list-shaped domain in one pass, pulling on any of the four feeds refreshes the whole app's backend state.

The four touched views:

- `ActivityFeedView` — the most-visited screen; `.refreshable` attaches to its `ScrollView`.
- `MedicationListView` — `.refreshable` attaches to the inner `List`.
- `AppointmentListView` — same.
- `DocumentListView` — same.

Empty-state branches (those that render `EmptyStateView` instead of a list) get the modifier too so the gesture still works when the local store is empty — the snapshot is the only path that can populate them in that state.

## Why this matters

- The user gains a familiar iOS gesture that does the obvious thing.
- When the realtime layer drops a frame (rare but possible) or hasn't yet drained a backlog after a long disconnect, the user can force resolution without restarting.
- Zero new infrastructure: `snapshotResync` already exists and is idempotent (Phase 23's upsert), so wiring it up is a UI-only change.
- Establishes the pattern. Future list views (CareMinuteListView, MembersListView, EmergencyContactsView, SOSHistoryView) can adopt the same one-line modifier in a follow-up.

## End state (definition of done)

1. **`ActivityFeedView`'s `ScrollView`** carries `.refreshable {}` that calls `realtimeClient.snapshotResync(circleIds: [circle.id], modelContext: modelContext)`.

2. **`MedicationListView`, `AppointmentListView`, `DocumentListView`** each carry the same modifier on their inner `List`. Empty-state branches also get the modifier when the parent container supports it (List itself is replaced by EmptyStateView; the wrapper view can still take a `.refreshable` because `EmptyStateView` is rendered inside the same outer `ZStack`/`VStack` — adding `.refreshable` on the empty branch requires a scroll-capable container, so we keep it on the populated branches only).

3. **`@Environment(BackendRealtimeClient.self)`** and **`@Environment(\.modelContext)`** are imported into each touched view.

4. **No double-snapshot guard.** Concurrent snapshots are tolerated because the underlying applicators are idempotent. The `isResyncing` flag may flicker but the worst case is wasted CPU/bandwidth — no correctness issue.

5. **Build + lint clean.**

## Architecture

```swift
// ActivityFeedView
private var scrollContent: some View {
    ScrollView { … }
    .refreshable {
        await realtimeClient.snapshotResync(
            circleIds: [circle.id],
            modelContext: modelContext
        )
    }
}

// MedicationListView / AppointmentListView / DocumentListView
List { … }
.refreshable {
    await realtimeClient.snapshotResync(
        circleIds: [circle.id],
        modelContext: modelContext
    )
}
```

## Risks and decisions

- **Pull during a reconnect-triggered snapshot.** Two concurrent snapshots run, both fully draining the eight-applicator TaskGroup. Each applicator's upsert is idempotent — no duplicates, no lost updates. The `isResyncing` flag will be set by whichever snapshot started last and cleared by whichever finishes last; brief flicker is acceptable.

- **Empty-state branches.** When the circle has no medications/appointments/documents, the view renders `EmptyStateView` directly, not a `List`. Attaching `.refreshable` to a non-scroll-capable container is a no-op. We keep the modifier on the populated branch only — the user can't see the empty branch and need to pull-refresh at the same time without first having a `List` (a paradox: if there are no items to scroll, pull-to-refresh has no anchor). Acceptable.

  Workaround for the future: wrap the empty state in a `List` with one placeholder row. Out of scope here.

- **Modal/sheet dismissal during refresh.** SwiftUI's `.refreshable` awaits the closure before clearing the spinner. If the user dismisses the screen mid-refresh, the closure continues running in detached state (the view's task lifetime). `snapshotResync` already drains to completion and updates `isResyncing` regardless of whose view is on screen. No leak.

- **Throttling.** No rate-limit on pull-to-refresh. iOS itself prevents users from triggering it more than once per second-or-so via the gesture's animation cycle. The applicators are cheap enough that this is fine.

- **Auth failure during refresh.** Each applicator handles its own auth errors via `logRefetchFailure(domain:error:)`. The pull-down spinner clears when the snapshot returns, even if every domain failed. The user sees no items refreshed but no crash. A future toast/banner for "Couldn't refresh — check connection" is out of scope.

## Out of scope (deferred follow-ups)

- **Other list views** (CareMinuteListView, MembersListView, EmergencyContactsView, SOSHistoryView). Same pattern, lower priority. Pick up in a follow-up phase.
- **Empty-state pull-to-refresh.** Requires wrapping `EmptyStateView` in a scrollable container with a placeholder row.
- **Toast on refresh failure.** Needs a shared in-app toast/banner system (not present in v1).
- **Visual indicator when the snapshot includes a SOS retraction.** Currently silent; a future enhancement could surface "1 stale alert cleared" inline.

## Definition of done checklist

- [x] `.refreshable {}` added to ActivityFeedView's ScrollView.
- [x] `.refreshable {}` added to MedicationListView, AppointmentListView, DocumentListView (on their inner `List`).
- [x] `@Environment(BackendRealtimeClient.self)` and `@Environment(\.modelContext)` added to each touched view.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 28+ candidates)

- Pull-to-refresh on remaining list views (CareMinuteListView, MembersListView, EmergencyContactsView, SOSHistoryView).
- Realtime circles-table applicator (rename / metadata fan-out) — requires new `notify_circles` backend trigger.
- Toast/banner system for transient sync errors.
- Per-(circle, table) cursor persistence to make snapshots delta-only.
