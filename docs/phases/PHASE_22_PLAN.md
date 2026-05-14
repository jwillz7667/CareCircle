# Phase 22 — Realtime SOS fan-out + dose / care-minute applicators

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 21 closed out realtime applicators for the five domains that already had circle-scoped REST list endpoints (activities, medications, appointments, members, contacts, documents). Three deferred domains remain:

| Table (NOTIFY)        | iOS model         | Why deferred                                                              |
| --------------------- | ----------------- | ------------------------------------------------------------------------- |
| `sos_events`          | `SOSEvent`        | Most user-visible; needs local-notification fan-out, not just data merge. |
| `dose_events`         | `DoseEvent`       | Per-row only — change frame carries dose UUID, no parent medication ID.   |
| `care_minute_entries` | `CareMinuteEntry` | Has a circle list endpoint; no special handling needed beyond the merge.  |

Phase 22 ships realtime applicators for all three, with the two pieces of new infrastructure those require:

1. **`GET /v1/doses/:id` backend route.** Returns `{id, medicationId, circleId, scheduledAt, takenAt, markedBy, status, notes}` for a single dose row. The realtime change frame for `dose_events` carries only `rowId`; without a per-row REST shape we'd have to refetch every medication's dose page, which is wasteful at any scale. This is the route Phase 21 explicitly called out as the Phase 22 prerequisite.
2. **Incoming-SOS local notification.** When a member triggers an SOS, the realtime fanout reaches other Circle devices' sockets in ≈ 100 ms. Inserting the row silently isn't enough — the whole point of SOS is that the user must be alerted *now*, even if the app is foregrounded (where APNs banners don't show by default). The applicator fires a local `UNNotificationRequest` with the same payload shape as `SOSCenter.postLocalAlert` so the alert pipeline (and notification category) stay consistent across self-triggered and incoming SOS events.

## End state (definition of done)

1. New backend route `GET /v1/doses/:id`:
   - Returns `404` when the dose is missing or not visible under RLS.
   - Response shape `{ id, medicationId, circleId, scheduledAt, takenAt, markedBy, status, notes }` — same per-dose shape as the existing `/v1/medications/:id/doses` list, plus the parent IDs so the iOS applicator can attach the dose to the right local row.
2. New iOS DTO `DoseByIdResponse` decoding the new route.
3. `applySosChange(circleId:modelContext:)` on `BackendRealtimeClient`:
   - List-refetches `/v1/circles/:id/sos`.
   - Idempotent insert by UUID (skips already-known rows).
   - For each newly inserted **non-canceled** row whose `triggeredBy` ≠ the current user's backend ID, fires a local `UNNotificationRequest` (category `SOS_EVENT`, interruption level `.timeSensitive`, identifier `sos.event.<UUID>` matching `SOSCenter.postLocalAlert`).
4. `applyDoseChange(rowId:modelContext:)`:
   - Fetches the new per-row endpoint.
   - Looks up the parent `Medication` locally by `dto.medicationId` (skip silently when not locally known — the medication will hydrate first on the next change frame or cold start).
   - Skips if the dose is already locally known.
   - Inserts a new `DoseEvent`, attaches to the parent medication, saves.
5. `applyCareMinuteChange(circleId:modelContext:)`:
   - List-refetches `/v1/circles/:id/care-minutes` via the existing endpoint.
   - Idempotent insert by UUID.
6. `dispatchChange` switch routes all three new tables.
7. Build + lint clean, backend tests pass.

## Out of scope (deferred to Phase 23+)

- **UPDATE / DELETE op handling.** The applicator inserts unknown rows only. SOS cancellation (UPDATE), medication soft-delete (DELETE), and dose retraction won't propagate live — they wait on the next cold-start hydration. Tracked as a cross-cutting follow-up.
- **Critical Alert entitlement.** The SOS notification still ships with `.timeSensitive` — when Apple grants the Critical Alert entitlement (application filed per `docs/CRITICAL_ALERTS_APPLICATION.md`), `SOSCenter.postLocalAlert` and the new realtime path will both bump to `.critical`. One follow-up commit, no rearchitecture.
- **Notification routing to a deep link.** Tapping the SOS local notification doesn't yet open `SOSHistoryView` filtered to that event. The `userInfo` payload carries the SOS UUID; deep-link wiring belongs in the notification-handling tab work.
- **Activity reactions / comments.** Same status as Phase 21 — fetched on-demand by `ActivityDetailView`. A live merge here is its own phase.
- **Single-row GETs for the other domains.** Phase 21 noted that `/v1/activities/:id`, `/v1/medications/:id`, etc. could replace the page-fetch. Phase 22 only adds the dose per-row route because dose is the one domain where the page-fetch path doesn't exist; the list-refetch optimization is still deferred for everything else.

## Architecture

```
BackendRealtimeClient.dispatchChange (extended)
  switch table {
    case "activities":         applyActivityChange         (Phase 20)
    case "medications":        applyMedicationChange       (Phase 21)
    case "appointments":       applyAppointmentChange      (Phase 21)
    case "circle_members":     applyMemberChange           (Phase 21)
    case "emergency_contacts": applyEmergencyContactChange (Phase 21)
    case "documents":          applyDocumentChange         (Phase 21)
    case "sos_events":         applySosChange              ← NEW
    case "dose_events":        applyDoseChange             ← NEW
    case "care_minute_entries": applyCareMinuteChange      ← NEW
    default:                   log + ignore
  }

applySosChange(circleId:, modelContext:)
  ├─ guard local Circle(id == circleId)
  ├─ response = GET /v1/circles/<id>/sos
  ├─ existingIDs = local SOSEvents in this circle, by UUID
  ├─ currentUserId = authState.lastVerifiedProfile?.id
  ├─ for dto in response.events:
  │     if existingIDs.contains(dto.id): continue
  │     row = mapper.makeSOSEvent(from: dto); row.circle = circle
  │     modelContext.insert(row); insertedRows.append((row, dto))
  ├─ if !insertedRows.isEmpty: modelContext.save()
  └─ for (row, dto) in insertedRows:
        if dto.triggeredBy != currentUserId && dto.canceledAt == nil:
          UNNotificationCenter.add(sosNotification(for: row, dto: dto))

applyDoseChange(rowId:, modelContext:)
  ├─ response = GET /v1/doses/<rowId>
  ├─ guard medication = local Medication(id == response.medicationId)
  ├─ guard !exists DoseEvent(id == response.id)
  ├─ dose = mapper.makeDoseEvent(from: dto-shaped subset)
  ├─ dose.medication = medication
  ├─ modelContext.insert(dose); modelContext.save()

applyCareMinuteChange(circleId:, modelContext:)
  ├─ identical pattern to Phase 21 list-refetch
```

## Wire format mapping

The backend trigger emits `TG_TABLE_NAME` verbatim:
`sos_events`, `dose_events`, `care_minute_entries`. The iOS dispatcher matches these literally — no rename.

## Risks and decisions

- **Loopback notification suppression.** The originator's device also receives the realtime change frame for their own SOS trigger. The applicator's idempotent insert guard (skip if row UUID already known) means no insert and no notification — `SOSCenter.fire()` already inserted + posted the local alert before the realtime fanout reaches the same device. No "is me" check is strictly needed for suppression, but we still gate on `dto.triggeredBy != currentUserId` as defense-in-depth in case of an edge case where the local row hasn't committed before the frame arrives.
- **Cancelled SOS suppression.** If an SOS is fired and immediately cancelled before the realtime fanout reaches a second device, the list-refetch will already see `canceledAt != nil`. We still insert the row (so the history view stays accurate) but skip the local notification — alerting someone about an SOS that was already cancelled is worse than not alerting at all.
- **Dose orphans.** If a dose change frame arrives before the parent medication is locally known (cold-start race, or a brand-new medication created milliseconds before its first dose), the applicator silently skips. The dose will be picked up by `BackendHydrator.hydrateDoseEvents` on the next foreground cold-start. The user-visible cost is a dose that doesn't show in the timeline until then.
- **Care-minute volume.** The `care_minute_entries` table has a `LIMIT 500` on its list endpoint. Family-scale circles produce a few entries per day, so 500 is months of headroom. If a circle ever exceeds that, the applicator will start missing the oldest rows — that's the trigger for paginating the endpoint, but well outside v1 scope.
- **`AuthState` dependency.** The SOS applicator needs the current user's backend UUID to skip self-triggered events. `BackendRealtimeClient` is constructed in `CareCircleApp` alongside `AuthState`; threading the auth state in as an init dependency is the cleanest path. Alternative — a closure `() -> String?` — adds one indirection for no benefit since both objects already share the `@MainActor`.

## Definition of done checklist

- [x] Backend `GET /v1/doses/:id` route + tests.
- [x] iOS `DoseByIdResponse` DTO.
- [x] `applySosChange` implemented, fires local notification on new non-canceled rows from other users.
- [x] `applyDoseChange` implemented, attaches to parent medication.
- [x] `applyCareMinuteChange` implemented.
- [x] `dispatchChange` routes `sos_events`, `dose_events`, `care_minute_entries`.
- [x] `BackendRealtimeClient` init takes a `currentBackendUserID` closure; `CareCircleApp` threads it in (closure captures `AuthState`).
- [x] xcodebuild + swiftformat + swiftlint clean.
- [x] Backend `pnpm --filter @carecircle/api test` clean for the new route.
- [x] Commit + push.

## Open follow-ups (Phase 23+ candidates)

- UPDATE / DELETE op handling across all applicators (SOS cancellation, medication soft-delete, etc.).
- Notification deep-link routing — tap an SOS alert to open `SOSHistoryView` scoped to that event.
- Activity reactions + comments live merge.
- Single-row GET optimization for the page-fetching applicators (activities, medications, appointments, members, contacts, documents).
- Snapshot-on-reconnect ledger for missed frames during long background.
