# Phase 23 — Realtime UPDATE / soft-delete handling across applicators

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phases 20 → 22 stood up a working realtime WebSocket pipeline. Nine domains now have applicators that react to row-level change frames. **But every applicator only inserts unknown rows.** When a member edits a medication name on iPhone A, soft-deletes an emergency contact, or cancels an SOS, the change does not propagate via the realtime path on iPhone B — it waits for the next cold-start hydration pass. The applicator's only effect on an UPDATE / DELETE frame today is to re-run an idempotent insert that finds nothing new and exits.

Phase 23 closes this gap. The applicator pattern becomes:

> **refetch → upsert → (where safe) soft-delete locally-known rows absent from the response**

Two sub-patterns, depending on whether the domain has a circle-scoped list endpoint:

1. **List-refetch domains** (medications, appointments, members, contacts, documents, activities, SOS, care-minutes) — refetch the list, for each row in the response either update the local row's fields or insert a new one, then optionally delete local rows whose UUIDs are absent from the response.
2. **Per-row domain** (doses) — `GET /v1/doses/:id` on every change frame. 2xx response → upsert. 404 → if locally known, delete the local `DoseEvent`.

## Why this matters

This phase makes the realtime path actually carry *all* state mutations, not just inserts. Without it, the realtime layer is a notification-only system that prompts the next cold-start to do the real work — defeating the latency claim ("≈ 100 ms") and forcing users to background+foreground the app to see a teammate's edit.

The biggest user-visible win is dose-status updates: caregiver on iPhone A taps "mark taken," family member watching the timeline on iPhone B sees the row flip from scheduled → taken without re-opening the app. Today that requires a cold-start.

## Pagination caveat — three domains skip the delete branch

The "absent from response = soft-deleted" rule only works when the list endpoint returns every non-deleted row for the circle. Three list endpoints are paginated and could legitimately omit rows that are not deleted:

| Domain        | List window         | Delete branch in realtime?              |
| ------------- | ------------------- | --------------------------------------- |
| activities    | 20 newest (cursor)  | NO — wait for cold-start hydration      |
| sos           | 50 newest           | NO — paginated *and* no `deleted_at`    |
| care-minutes  | 500 newest          | NO — paginated, even if rarely tripped  |
| medications   | full (deleted_at IS NULL) | YES                              |
| appointments  | full                | YES                                     |
| members       | full                | YES                                     |
| contacts      | full                | YES                                     |
| documents     | full                | YES                                     |
| doses         | per-row fetch       | YES — 404 from per-row → local delete   |

For the three paginated domains, applying delete-from-absence would falsely delete every older row that fell off the page on every refetch. Cold-start hydration already performs a comprehensive sweep with pagination cursors; soft-delete propagation for those three domains stays on that path in v1. The trade-off is documented in §Out of scope.

## End state (definition of done)

1. **New per-domain `updateX(_:from:)` mappers** in `BackendHydratorMappers`, one per row type, mutating only backend-authoritative fields on an existing local row. CloudKit-only fields (photo/audio blobs on `Activity`, encrypted blob triple + `visibilityRolesRaw` on `Document`, `milesDriven` on `CareMinuteEntry`, dose-to-medication relationship, etc.) are *not* touched.

2. **All eight list-refetch applicators upgraded to upsert.** For each row in the response: if a local row with the same UUID exists, run the update mapper; otherwise insert as today.

3. **Five domains (medications, appointments, members, contacts, documents) gain a soft-delete sweep.** After the upsert pass, locally-known UUIDs absent from the response are removed. SwiftData's cascade rules carry the deletion through to relationships where applicable (e.g. deleting a `Medication` cascades to its `DoseEvent` rows via `inverse: \DoseEvent.medication`).

4. **Dose applicator gains UPDATE and DELETE branches.** Per-row fetch returns 2xx → if the local row exists, update its fields; otherwise insert. Per-row fetch returns 404 → if the row is locally known, delete the local `DoseEvent`.

5. **SOS applicator's upsert still gates the local notification on the *insert* path only.** Cancellation frames update `canceledAt` / `canceledByAppleUserID` on an existing row and do *not* re-post the UNNotificationRequest.

6. **Build + lint clean** on iOS; backend has no changes this phase.

## Architecture

```
BackendRealtimeClient.dispatchChange (unchanged switch)
  ├─ activities          → applyActivityChange         (upsert; no delete)
  ├─ medications         → applyMedicationChange       (upsert + delete)
  ├─ appointments        → applyAppointmentChange      (upsert + delete)
  ├─ circle_members      → applyMemberChange           (upsert + delete)
  ├─ emergency_contacts  → applyEmergencyContactChange (upsert + delete)
  ├─ documents           → applyDocumentChange         (upsert + delete)
  ├─ sos_events          → applySosChange              (upsert; no delete; notif on insert only)
  ├─ dose_events         → applyDoseChange             (upsert via per-row; 404 → delete)
  └─ care_minute_entries → applyCareMinuteChange       (upsert; no delete)

applyXChange (list-refetch domains)
  ├─ response = GET /v1/circles/<id>/<domain>
  ├─ localByID = [UUID: M] for this circle
  ├─ responseIDs = Set<UUID>
  ├─ for dto in response.rows:
  │     responseIDs.insert(dto.id)
  │     if let existing = localByID[dto.id]:
  │         BackendHydratorMappers.updateX(existing, from: dto)
  │     else:
  │         row = makeX(from: dto); row.circle = circle; insert(row)
  ├─ if domain in {medications, appointments, members, contacts, documents}:
  │     for (id, row) in localByID where !responseIDs.contains(id):
  │         modelContext.delete(row)
  └─ save()

applyDoseChange(rowId:)
  ├─ try response = GET /v1/doses/<rowId>
  │     ├─ 2xx: existing = local DoseEvent(id == rowId)
  │     │       if existing: updateDoseEvent(existing, from: response.asDoseDTO)
  │     │       else: insert new with parent medication
  │     ├─ 404: existing = local DoseEvent(id == rowId)
  │     │       if existing: modelContext.delete(existing); save()
  │     └─ other error: log + return (don't delete on transient failure)
```

## Update-mapper field matrix

Per-domain authoritative-field lists (the fields each `updateX` writes). Fields not listed are CloudKit-only or set once at insert and never updated.

| Domain         | Mutable fields written by update mapper                                                                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Activity       | `body`, `typeRaw`, `createdAt` (occurredAt rename)                                                                                                                                     |
| Medication     | `name`, `dosage`, `formRaw`, `statusRaw`, `colorHex`, `scheduleJSON`, `startDate`, `endDate`, `updatedAt`                                                                               |
| Appointment    | `title`, `provider`, `location`, `startsAt`, `durationMinutes`, `prepNotes`, `transportResponsibleAppleUserID`, `reminderOffsetsMinutes`, `updatedAt`                                   |
| Member         | `displayName`, `roleRaw`, `statusRaw`, `joinedAt`, `invitedAt`                                                                                                                          |
| EmergencyContact | `name`, `relationship`, `phoneE164`, `isPrimary`, `isMedical`, `sortOrder`, `updatedAt`                                                                                              |
| Document       | `title`, `typeRaw`, `mimeType`, `sizeBytes`, `issuedAt`, `expiresAt`, `uploadedByAppleUserID`, `backendObjectKey`, `updatedAt`                                                          |
| SOSEvent       | `triggeredByDisplayName` (only when looked up), `canceledAt`, `canceledByAppleUserID`                                                                                                  |
| CareMinuteEntry | `caregiverAppleUserID`, `serviceCodeRaw`, `serviceDescription`, `startedAt`, `endedAt`, `notes`, `fiscalIntermediary`, `updatedAt`                                                     |
| DoseEvent      | `scheduledAt`, `takenAt`, `statusRaw`, `markedByAppleUserID`, `notes`, `updatedAt`                                                                                                     |

## Risks and decisions

- **No race-aware versioning.** The applicator trusts the response. If two devices update the same row within a few ms, last-write-wins on the backend (current `updated_at` semantics) and the realtime fan-out delivers the final state to both. Adding LWW comparisons against `updatedAt` is unnecessary because the *response* is already the post-LWW truth.

- **Soft-delete races on documents.** A user reading a `Document` whose UUID just got soft-deleted will observe the row disappear from their list. The encrypted blob in CloudKit isn't cleared by this phase — that's CloudKit's own deletion path, which still runs through the existing `Document` deletion code. Phase 23's delete-from-absence sweep removes the SwiftData row; if it had a CKAsset, CloudKit will reconcile on its next pass. Acceptable v1 behavior.

- **Dose 404 distinguished from transient network failure.** The dose applicator must only treat `APIError.http(status: 404, …)` as "deleted." Other errors (transport, 5xx) leave the local row alone — losing a row to a network blip is worse than waiting for the next change frame.

- **Cascade deletes from `Medication` removal.** SwiftData's `@Relationship(deleteRule: .cascade, inverse: \DoseEvent.medication)` already wipes related dose rows when a `Medication` is deleted. The medication applicator's delete branch doesn't need to manually sweep doses — SwiftData does it.

- **Member self-removal.** If the current user is removed from a Circle on the backend, the members refetch will not include their own row. The member applicator's delete sweep would then delete the local `Member` for the current user. That's the correct outcome — but it raises a separate question (does removing the local `Member` cascade-delete the `Circle`? It does not; `Member.circle` is the inverse side without a cascade rule, and the Circle is owned via the share). The user will see the Circle empty out as further applicators run and delete its medications, appointments, etc. The Circle row itself stays until the realtime layer sees `circles` changes — out of scope for v1 (no `circles` applicator).

- **CloudKit / SwiftData ordering on update.** SwiftData mutations on a persistent model push through to CloudKit on the next sync cycle. There's no two-way conflict resolution between the backend update mapper writing to a local row and the same row being mutated in CloudKit by another device. In practice this race window is small (both updates eventually converge on the latest backend value), and the v1 sharing pattern keeps a single backend as the source of truth for these fields.

- **`SOSEvent.triggeredByDisplayName` only updated when lookup succeeds.** The existing `lookupMemberDisplayName` resolves the display name from a local `Member`. On an UPDATE for a known SOS row, the local row's display name was already set on the original insert; re-running the lookup might find a newly-renamed member or might fail. To avoid blanking the name on a failed lookup, the SOS update mapper *only* overwrites the display name when the lookup returns a non-empty value.

## Out of scope (deferred follow-ups)

- **Soft-delete via realtime for activities, sos, care-minutes.** The paginated list endpoints cannot reliably distinguish "deleted" from "older than the page boundary." Cold-start hydration handles these correctly. A future phase can add date-cursored sweep windows or per-row GETs (analogous to `/v1/doses/:id`) to close this gap.

- **Notification retraction on SOS cancellation.** If iPhone B already posted the local SOS notification and then receives the cancellation UPDATE, the notification stays in the tray. Removing it requires `removeDeliveredNotifications(withIdentifiers:)` plumbing — deferred. Tapping it eventually opens the (then-canceled) event view, which is acceptable v1 UX.

- **Activity reactions / comments live merge.** Unchanged from prior phases — fetched on-demand by `ActivityDetailView`.

- **Circle-level realtime applicator.** Renames, owner changes, and the user-being-removed-from-circle path don't trigger a `circles` applicator yet. The current realtime layer doesn't subscribe to that table.

## Definition of done checklist

- [x] `BackendHydratorMappers` gains nine `updateX(_:from:)` mappers (Activity, Medication, Appointment, Member, EmergencyContact, Document, SOSEvent, CareMinuteEntry, DoseEvent).
- [x] `applyActivityChange` upserts (no delete branch).
- [x] `applyMedicationChange`, `applyAppointmentChange`, `applyMemberChange`, `applyEmergencyContactChange`, `applyDocumentChange` upsert + delete-from-absence.
- [x] `applySosChange` upserts; notification still gated on insert path only.
- [x] `applyCareMinuteChange` upserts (no delete branch).
- [x] `applyDoseChange` upserts on 2xx; deletes local row on 404; ignores other errors.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 24+ candidates)

- Notification retraction (tray cleanup) when SOS cancellation fans out.
- Per-row GET for SOS and activities so paginated domains can join the realtime delete path.
- Two-way conflict resolution / versioned LWW between backend and CloudKit edits to the same row.
- Circles-table applicator (rename, owner change, member-removed-from-circle local cleanup).
- Snapshot-on-reconnect ledger for missed frames during long background sleeps (already noted in Phase 22 follow-ups).
