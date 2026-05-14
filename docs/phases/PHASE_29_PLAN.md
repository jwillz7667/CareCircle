# Phase 29 — Pull-to-refresh on empty-state branches

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phases 27 and 28 wired `.refreshable {}` into every list-shaped view, but the **empty-state branches** (where the view renders `EmptyStateView` instead of a `List`) were explicitly deferred. In those branches the pull-down gesture has no scroll anchor, so the user can't trigger a snapshot resync from a fresh-install / signed-in-but-not-yet-hydrated state.

Phase 29 closes that gap by wrapping the `EmptyStateView` in a `ScrollView { … }.refreshable { … }` whose content uses `containerRelativeFrame(.vertical)` so the empty state still fills the viewport vertically (no centred-content collapse).

Five views are affected:

- `MedicationListView` — empty branch wraps a `VStack { EmptyStateView, DisclaimerFooter }`; the wrap goes around that VStack.
- `AppointmentListView` — empty branch is a bare `EmptyStateView`.
- `DocumentListView` — same.
- `EmergencyContactsView` — same.
- `SOSHistoryView` — same.

The other three previously-touched views already have a scroll-capable container in the empty branch:

- `ActivityFeedView` — already wraps everything in `ScrollView`.
- `CareMinuteListView` — always uses `ScrollView`.
- `MembersListView` — always uses `List` (no separate empty branch).

## Why this matters

- After Phase 29, **every** backend-backed list view supports pull-to-refresh regardless of whether the local store is empty or populated.
- Closes the specific edge case: user signs in on a fresh device, hydration hasn't completed, lists are empty, network glitches — without pull-to-refresh on empty states the user must force-close the app.
- Establishes the canonical pattern (`ScrollView { … }.containerRelativeFrame(.vertical).refreshable { … }`) for any future view that needs the same affordance.

## End state (definition of done)

1. Each of the five empty-state branches uses:

   ```swift
   ScrollView {
       <empty content>
           .containerRelativeFrame(.vertical)
   }
   .refreshable {
       await realtimeClient.snapshotResync(
           circleIds: [circle.id],
           modelContext: modelContext
       )
   }
   ```

2. The populated branches are unchanged — Phase 27/28's `.refreshable` on the inner `List` stays as-is.

3. Build + lint clean.

## Architecture / pattern

```swift
@ViewBuilder
private var content: some View {
    if circle.medications.isEmpty {
        ScrollView {
            VStack(spacing: 0) {
                EmptyStateView(...)
                DisclaimerFooter()
            }
            .containerRelativeFrame(.vertical)
        }
        .refreshable {
            await realtimeClient.snapshotResync(
                circleIds: [circle.id],
                modelContext: modelContext
            )
        }
    } else {
        List { ... }
            .refreshable { ... }
    }
}
```

`containerRelativeFrame(.vertical)` (iOS 17+) is the right API here: it sizes the inner content to the ScrollView's viewport height so the visual layout matches the prior bare-EmptyStateView rendering (centred content, full-bleed background) while still giving the user a scroll anchor for pull-to-refresh.

## Risks and decisions

- **`containerRelativeFrame(.vertical)` is iOS 17+.** We deploy at 17.0 minimum (lowered 2026-05-13 for TestFlight reach). Safe.

- **Visual diff.** The ScrollView wrapper introduces no visible padding or chrome by default. The empty state should look identical to the prior rendering. The only behavioural change is that the area is now scrollable (with no content overflow, the scroll has zero range — only the pull-down rubber-band is engaged).

- **Concurrent refresh on populated → empty transition.** If a refresh happens to empty the local store mid-refresh, SwiftUI may rebuild the view tree from `List` → `ScrollView`. `.refreshable` awaits its closure; the closure runs against the snapshot model, not the view, so the result is unaffected. The new ScrollView won't show a spinner because the previous spinner was on the now-discarded List; brief visual artifact but no correctness issue.

- **Realtime client environment availability in empty branch.** Both `@Environment(BackendRealtimeClient.self)` and `@Environment(\.modelContext)` are struct-level declarations from Phase 27/28 — in scope across both branches. No additional environment wiring needed.

## Out of scope (deferred follow-ups)

- **Reusable `RefreshableEmptyState` view.** Inlining the wrap five times keeps the diff narrow. If we add a sixth empty-state branch later, extract it then.
- **Visual feedback during empty-state refresh** (e.g., "Checking for updates…" text). Out of scope; the system pull-to-refresh spinner is enough.
- **Toast on refresh failure** — still deferred. Needs a shared toast component.
- **Realtime circles-table applicator** — still deferred. Needs a `notify_circles` backend trigger.

## Definition of done checklist

- [x] MedicationListView empty branch wrapped.
- [x] AppointmentListView empty branch wrapped.
- [x] DocumentListView empty branch wrapped.
- [x] EmergencyContactsView empty branch wrapped.
- [x] SOSHistoryView empty branch wrapped.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 30+ candidates)

- Realtime circles-table applicator (rename / metadata fan-out) — requires `notify_circles` backend trigger.
- Toast/banner system for transient sync errors.
- Per-(circle, table) cursor persistence to make snapshots delta-only.
- Visual indicator (small spinner pill) in nav bar when `realtimeClient.isResyncing` is true.
