# Phase 16 — Inbound hydration (cold-start vertical)

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 15 made every iOS mutation flow outward through the backend
queue. Phase 16 closes the opposite leg: the iOS app reads from the
backend on launch and **hydrates SwiftData when the device has no
local data yet**. This proves the inbound read pipeline end-to-end
without invading CloudKit's authority over rows it already replicated.

We deliberately scope hydration to **cold-start only**: when SwiftData
holds zero rows of a domain for a circle, we trust the backend as the
source of truth and insert those rows locally. When SwiftData already
has rows for that domain (the CloudKit case), this phase **does
nothing** — full row-level merge is Phase 17.

## End state (definition of done)

1. A new `BackendHydrator` service in `Services/Backend/` that, given a
   `Circle` + `ModelContext`, pulls the user's data from the backend
   and inserts it locally **only when the local store is empty for
   that domain**.
2. New `APIClient.send` calls for each read route:
   - `GET /v1/circles/:circleId/activities` (paginated)
   - `GET /v1/circles/:circleId/medications`
   - `GET /v1/circles/:circleId/appointments`
   - `GET /v1/circles/:circleId/emergency-contacts`
   - `GET /v1/circles/:circleId/members`
   - `GET /v1/circles/:circleId/care-minutes`
   - `GET /v1/circles/:circleId/sos`
3. The hydrator runs from `RootView` once per launch when the user is
   signed in and the backend session is verified. Failure is logged
   and silent — CloudKit still hydrates everything we already had.
4. A "Pull from backend" debug row in MoreView's "Backend sync"
   section triggers the hydrator manually, exposing the last-run
   timestamp and any error.
5. `xcodebuild` succeeds on iPhone 16 Pro Max simulator. swiftlint
   exits 0 with no new errors.
6. No regression: existing offline behavior keeps working; CloudKit
   sync continues unchanged.

## Out of scope (explicitly deferred)

- **Documents.** Encrypted blobs depend on the per-circle DEK
  distribution flow (CKShare-bound today). Phase 17 handles blob
  upload + key reconciliation in one shot.
- **Recipient (`CareRecipient`).** One-per-circle row tied to
  ownership/consent semantics — needs its own audit.
- **Row-level merge.** When local and remote both have versions of
  the same row, the merge policy + conflict UI are Phase 17.
- **Realtime push (WebSocket).** Phase 19 still.
- **Inbound dose-event hydration.** Per-medication endpoint requires
  N+1 fetches; defer until medication merge is settled.

## Architecture

```
RootView.onAppear (signed in + verified)
  └─► BackendHydrator.hydrate(circle:modelContext:)
        ├─► fetchActivities (paginated)
        ├─► fetchMedications
        ├─► fetchAppointments
        ├─► fetchEmergencyContacts
        ├─► fetchMembers
        ├─► fetchCareMinutes
        └─► fetchSOS
              each:
                if localCount(forDomain, circle) == 0:
                    insert rows
                else:
                    skip (CloudKit owns this domain locally)
```

Each fetch returns a domain-specific DTO with `Codable, Sendable,
Equatable` and snake-case-decoding handled by the existing
`APIClient.decoder`.

`BackendHydrator` is `@MainActor` and holds the SwiftData
`ModelContext` for the lifetime of one hydration run. It logs every
no-op skip + every insert count so we can verify behavior in
Console.app.

## Files to create

- `CareCircle/Sources/Services/Backend/BackendHydrator.swift` — the
  orchestrator described above.
- `CareCircle/Sources/Services/Backend/BackendReadDTOs.swift` — all
  per-route response DTOs (`ActivitiesResponse`,
  `MedicationsResponse`, etc.). One file keeps the read surface
  visible in one place.

## Files to modify

- `CareCircle/Sources/Services/Backend/APIClient.swift` — no changes
  needed; existing `send<Response>` overloads suffice.
- `CareCircle/Sources/App/RootView.swift` — kick off `hydrate` once
  per launch after `verifyBackendSession` resolves.
- `CareCircle/Sources/Features/More/MoreView.swift` — add a debug row
  exposing "Pull from backend now" with the last-run timestamp + last
  error from `BackendHydrator`.
- `CareCircle/Sources/Features/Auth/AuthState.swift` — expose the
  hydrator instance so the scene-phase observer can invoke it.

## Wire-format expectations (from backend survey)

| route                                         | top-level key       | row fields used                                                                                    |
| --------------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------- |
| `GET /v1/circles/:id/activities?cursor=…`     | `activities`        | `id, authorUserId, type, headline, content, occurredAt, version, entities`                          |
| `GET /v1/circles/:id/medications`             | `medications`       | `id, name, dosage, form, status, schedule, startDate, endDate`                                      |
| `GET /v1/circles/:id/appointments`            | `appointments`      | `id, title, provider, location, startsAt, durationMinutes, transportResponsible, prepNotes`         |
| `GET /v1/circles/:id/emergency-contacts`      | `contacts`          | `id, name, relationship, phone, isPrimary, isMedical, sortOrder`                                    |
| `GET /v1/circles/:id/members`                 | `members`           | `id, userId, role, status, displayName, joinedAt, invitedAt`                                        |
| `GET /v1/circles/:id/care-minutes`            | `entries`           | `id, caregiverUserId, serviceCode, serviceDescription, startedAt, endedAt, notes, fiscalIntermediary` |
| `GET /v1/circles/:id/sos`                     | `events`            | `id, triggeredBy, triggeredAt, canceledAt, locationLat, locationLng`                                |

## Risks / decisions

- **Cold-start gate is conservative.** If a device has CloudKit data
  but the backend lags behind, we'll skip hydration here and the
  backend-only rows stay invisible until Phase 17 merge. Acceptable
  for now — better than risking a duplicate-insert storm.
- **Owner identity mismatch.** Backend `authorUserId` is a UUID; the
  local rows use Apple-user-IDs. The hydrator stores the backend UUID
  in a passthrough column we'll need later for merge — for activities
  the existing `Activity.authorAppleUserID` covers this when the
  backend populates it via Apple JWT subject; if not, we fall back to
  a hyphen-stripped UUID as a placeholder so the row is consistent.
- **Members.** We only hydrate `displayName + role + status` — the
  Apple-user-ID linkage stays with the CKShare acceptance path.
- **Activities pagination.** Cap at 5 pages * 50 = 250 rows per
  hydration to keep launch latency bounded. Older content can be
  pulled on demand.

## Definition of Done (checklist)

- [ ] `BackendHydrator` + `BackendReadDTOs` files exist.
- [ ] `RootView` invokes hydrator after session verification.
- [ ] MoreView debug row visible when signed in.
- [ ] `xcodebuild build` succeeds; swiftlint exits 0.
- [ ] One commit, conventional-commits message, no AI attribution.

## Open follow-ups (Phase 17+)

- Row-level merge between local and remote.
- Document blob upload via MinIO presign + key reconciliation.
- Per-medication dose-event hydration.
- Realtime WebSocket tap.
