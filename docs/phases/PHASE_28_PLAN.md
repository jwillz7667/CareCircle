# Phase 28 — Pull-to-refresh on remaining list views

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 27 wired `.refreshable {}` into the four primary content views (ActivityFeedView, MedicationListView, AppointmentListView, DocumentListView). Phase 28 extends the same one-line modifier to the remaining four list views so every screen with a list-shaped feed of backend data gets the same pull-to-refresh affordance:

- `CareMinuteListView` — pulls on its outer `ScrollView`.
- `MembersListView` — pulls on its `List`.
- `EmergencyContactsView` — pulls on its `List` (when non-empty).
- `SOSHistoryView` — pulls on its `List` (when non-empty).

No new logic; this is pure pattern propagation.

## Why this matters

- Consistency: every list-shaped screen behaves the same way.
- Closes the user-facing gap where some views silently fail to update when realtime drops a frame.
- After Phase 28, "pull to refresh" works on every backend-backed list view in the app.

## End state (definition of done)

1. Each of the four views imports `@Environment(BackendRealtimeClient.self)` (and `@Environment(\.modelContext)` where not already present).
2. Each list/scroll container carries `.refreshable {}` that awaits `realtimeClient.snapshotResync(circleIds: [circle.id], modelContext: modelContext)`.
3. Build + lint clean.

## Risks and decisions

Identical to Phase 27. No new risk surface.

## Definition of done checklist

- [x] CareMinuteListView wired.
- [x] MembersListView wired.
- [x] EmergencyContactsView wired.
- [x] SOSHistoryView wired.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.
