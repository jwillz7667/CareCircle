# Phase 21 — Realtime applicators for medications, appointments, members, emergency contacts, documents

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 20 proved the realtime applicator pattern with activities. The
`BackendRealtimeClient` is online; the wire frame is decoded; the
activity merge path is idempotent. The only `change` table it acts on
is `activities`. Every other table currently logs "no applicator yet"
and the local copy stays stale until the next cold-start hydration.

Phase 21 expands the applicator surface to cover five more domains:

| Table (NOTIFY)       | iOS model           | Backend fetch                              |
| -------------------- | ------------------- | ------------------------------------------ |
| `medications`        | `Medication`        | `GET /v1/circles/:id/medications`          |
| `appointments`       | `Appointment`       | `GET /v1/circles/:id/appointments`         |
| `circle_members`     | `Member`            | `GET /v1/circles/:id/members`              |
| `emergency_contacts` | `EmergencyContact`  | `GET /v1/circles/:id/emergency-contacts`   |
| `documents`          | `Document`          | `GET /v1/circles/:id/documents`            |

Each applicator follows the same shape as `applyActivityChange`: refetch
the per-circle list, diff against local IDs by UUID, insert the rows
this device hasn't seen yet, save once at the end. The same idempotency
property holds — local writes (which already round-trip through
`SyncEngine`) stay authoritative because the row is already present
locally before the change frame arrives.

Documents are the most interesting case: a backend INSERT triggered by
another member's upload creates a *placeholder* row locally (empty
ciphertext, populated `backendObjectKey`). The Phase 19 prefetch
sweeper, already wired into `RootView`, picks it up on the next
foreground tick and downloads + writes the ciphertext back into the
SwiftData row. Net effect: a doc uploaded on another phone surfaces on
this phone within a few seconds with the "Backend only" badge, then
flips to readable a moment later.

## Out of scope (deferred to Phase 22+)

- **Dose events.** The change frame carries `rowId = dose UUID`, but
  the backend only exposes `GET /v1/medications/:id/doses` (the parent
  medication's list). Without a per-row endpoint or a per-medication
  index on rowId, the cheapest correct path would be to refetch every
  medication's dose list per change frame — not worth it. Either a new
  `GET /v1/doses/:id` route or a per-medication LRU cache lookup based
  on stored medication↔dose mapping is the Phase 22 work.
- **Care minute entries.** No per-row endpoint. Same shape as dose
  events.
- **SOS events.** No per-row endpoint. The most user-visible domain on
  this list (an SOS triggered by another member should fan out *now*),
  so it gets its own follow-up phase — likely paired with a backend
  `GET /v1/sos/:id` route plus an iOS local-notification flow so
  members are alerted even if the app is in the background.
- **Activity reactions / comments.** Backend trigger fires
  `activity_reactions` and `activity_comments` change frames but the
  iOS app fetches these on demand within `ActivityDetailView`, not at
  the activity-list level. Live updates here will pair with a Phase 22+
  reaction/comment count refresh.
- **Single-row GET optimization.** Phase 20's follow-up noted that
  `/v1/activities/:id` could replace the page fetch. That change is
  deferred — list-refetch keeps the applicator code uniform across
  domains and the page sizes are bounded (members/contacts/documents
  ≤ 200 each on family-scale circles).
- **UPDATE / DELETE op handling.** The applicator inserts unknown
  rows; it doesn't apply field-level edits or soft-deletes. Edits to
  existing rows still rely on cold-start hydration to re-pull the
  page, which means a member who edits a medication name won't have it
  propagate live to other devices. That's tracked separately.

## Architecture

```
BackendRealtimeClient.dispatchChange (Phase 20, extended)
  switch table {
    case "activities":         applyActivityChange         (Phase 20)
    case "medications":        applyMedicationChange       ← NEW
    case "appointments":       applyAppointmentChange      ← NEW
    case "circle_members":     applyMemberChange           ← NEW
    case "emergency_contacts": applyEmergencyContactChange ← NEW
    case "documents":          applyDocumentChange         ← NEW
    default:                   log + ignore
  }

apply<Domain>Change(circleId:, modelContext:)
  ├─ guard local Circle(id == circleId) exists
  ├─ response = apiClient.send(GET /v1/circles/<id>/<domain>)
  ├─ existingIDs = local <Domain> rows in this circle, by UUID
  ├─ for dto in response.<domain>:
  │     if not existingIDs.contains(dto.id):
  │       row = mapper.make<Domain>(from: dto)
  │       row.circle = circle
  │       modelContext.insert(row)
  ├─ if inserted > 0: modelContext.save()
  └─ log
```

## Risks and decisions

- **Page-fetch on every change.** Five new fetch paths per circle ×
  one fetch per change frame is fine at family scale (≤ 5 members,
  ≤ tens of rows per domain). At larger scales a single-row GET would
  be required; that's the Phase 22 optimization.
- **Document placeholder + prefetch race.** When a `documents` INSERT
  frame arrives, the applicator inserts a placeholder. The Phase 19
  prefetch sweeper is triggered by `RootView.maybeHydrateOnce` and
  scene-phase `.active`, not by frame arrival — so the placeholder
  sits as "Backend only" until the user backgrounds and foregrounds.
  Acceptable for v1; firing `triggerPrefetch` after a successful doc
  insert is a one-line follow-up if it bothers users in dogfood.
- **Member changes and CKShare drift.** When the backend emits a
  `circle_members` INSERT (e.g., new member joined via invitation
  code), the local copy of the `Member` row updates immediately, but
  the CloudKit `CKShare` participant list is a separate store that
  only updates on `CircleSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`.
  Members joining via the iOS share-acceptance flow trigger both; a
  member joining via backend-only invitation code (when that lands)
  won't update CloudKit at all. Phase 21 doesn't introduce regressions
  here — the existing CKShare path keeps working.
- **Concurrent re-entry.** Two change frames for the same table
  arriving within milliseconds will both fire a page fetch. The
  applicator's idempotency property (insert only unknown UUIDs)
  guarantees correctness; the cost is one duplicate network round-trip.
  No per-table debounce in v1.

## Wire format mapping

The backend trigger emits `TG_TABLE_NAME` directly (`circle_members`,
not `members`; `emergency_contacts`, not `emergencyContacts`). The
iOS dispatcher matches that table name literally — no camelCase
conversion.

## Definition of done checklist

- [x] `applyMedicationChange(circleId:modelContext:)` implemented.
- [x] `applyAppointmentChange(circleId:modelContext:)` implemented.
- [x] `applyMemberChange(circleId:modelContext:)` implemented.
- [x] `applyEmergencyContactChange(circleId:modelContext:)` implemented.
- [x] `applyDocumentChange(circleId:modelContext:)` implemented.
- [x] `dispatchChange` switch routes all five table names.
- [x] xcodebuild + swiftformat + swiftlint clean.
- [x] Commit + push.

## Open follow-ups (Phase 22+ candidates)

- `GET /v1/doses/:id`, `GET /v1/sos/:id`, `GET /v1/care-minutes/:id`
  backend routes + iOS applicators.
- UPDATE / DELETE op handling for existing applicators.
- Document prefetch trigger after a `documents` INSERT applicator run.
- Activity reactions + comments live merge.
- Single-row GET optimization across all applicators (replaces page
  fetch).
