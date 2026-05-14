# Phase 15 — Outbound sync expansion + backend session proof-of-life

**Status:** in progress
**Started:** 2026-05-13

## What this is

Phase 14 shipped one vertical slice (Apple-token → backend exchange,
plus `create_activity` op flowing through the durable queue). This phase
extends the same write-through pattern to **every other mutating user
action** in the app, and adds a tiny inbound call — `GET /v1/me` — so
the UI can confirm the device is talking to the backend rather than
optimistically assuming the session is healthy.

Full inbound hydration (pulling activities, medications, etc. from the
backend on launch and reconciling with CloudKit) is the larger
architectural problem and is deferred to **Phase 16**.

## End state (definition of done)

1. Every user-initiated mutation that today writes to SwiftData/CloudKit
   also enqueues a `PendingOperation`. New op types:
   - `create_medication` (AddMedicationView)
   - `mark_dose_taken` and `mark_dose_skipped` (MedicationDetailView /
     MedicationDoseRow)
   - `create_appointment` (AddAppointmentView)
   - `create_member` (AddMemberView — invitation creation)
   - `create_emergency_contact` (AddEmergencyContactView)
   - `create_care_minute_entry` (AddCareMinuteEntryView)
   - `create_sos_event` (SOSCenter trigger)
   - `create_document` (AddDocumentView — metadata only; the encrypted
     blob still lives on CloudKit until Phase 17 introduces the MinIO
     presign flow)
2. `BackendAuthService.fetchMe()` returns a `BackendUserProfile` shaped
   to match `GET /v1/me` (`id`, `email`, `displayName`,
   `isPrivateEmail`, `createdAt`).
3. The app pings `/v1/me` on launch (after auth bootstrap) and on
   scenePhase → active. The response is cached on `AuthState` so the UI
   can read `lastVerifiedBackendUser`.
4. `MoreView`'s existing "Backend sync" section grows a second row:
   "Session: verified as <displayName>" (✓) or "Session unverified"
   when `fetchMe` last failed.
5. `xcodebuild` succeeds on iPhone 16 Pro Max simulator. swiftlint
   exits 0 with no new errors.
6. No behavior regression: app still works fully offline; backend
   failures stay best-effort.

## Out of scope (explicitly deferred)

- **Inbound state hydration** — Phase 16. Reconciling backend rows
  against CloudKit-replicated SwiftData rows needs its own design and
  test plan.
- **Document blob upload to MinIO** — Phase 17. This phase mirrors the
  document *metadata* row only.
- **APNs device registration** — Phase 18. Needs the `.p8` key.
- **WebSocket realtime** — Phase 19.

## Architecture

Same pattern as Phase 14:

```
SwiftUI write site (e.g. AddMedicationView.save())
  └─► SwiftData / CloudKit write (unchanged)
  └─► syncEngine.enqueueMedicationCreate(med)
        └─► PendingOperation row
              └─► SyncEngine drain → POST /v1/sync/batch
```

`fetchMe()` runs out-of-band of the queue — it's a read, not a
mutation, so it goes through `apiClient.send` directly. Result is
stored on `AuthState.lastVerifiedProfile`.

## Files to create

- None. All work happens in existing services / views.

## Files to modify

- `CareCircle/Sources/Services/Backend/SyncOperation.swift`
  - Extend `SyncOperationType` with the new constants.
  - Add 9 new `Create*Payload` / `MarkDose*Payload` structs mirroring
    the backend's documented field shapes (snake_case becomes camelCase
    over the wire because the encoder uses default key strategy and
    backend handlers expect camelCase JSON per the backend audit).
- `CareCircle/Sources/Services/Backend/SyncEngine.swift`
  - Add 9 new `enqueue…(_:)` methods. Each method:
    1. Builds the payload struct.
    2. Encodes it with `self.encoder`.
    3. Inserts a `PendingOperation` on `modelContainer.mainContext`.
    4. Saves the context.
    5. Calls `refreshPendingCount()` and `triggerDrain()`.
  - Factor the boilerplate into a private helper
    `enqueue(operationType:circleId:payload:)` so the new methods stay
    one or two lines each.
- `CareCircle/Sources/Services/Backend/BackendAuthService.swift`
  - Add `func fetchMe() async throws(APIError) -> BackendUserProfile`.
- `CareCircle/Sources/Services/Backend/BackendUserProfile.swift` (new
  inside Backend folder)
  - `nonisolated struct BackendUserProfile: Codable, Sendable, Equatable`.
- `CareCircle/Sources/Features/Auth/AuthState.swift`
  - Track `lastVerifiedProfile: BackendUserProfile?` and
    `lastVerifyError: APIError?` (private(set) observable).
  - Add `func verifyBackendSession() async` — calls
    `backendAuthService.fetchMe()` and stores the result. Failures log
    and clear the cached profile.
  - Call `verifyBackendSession()` from `bootstrap()` when signed in,
    after `exchangeBackendSession()` succeeds, and expose it for the
    app's scenePhase observer.
- `CareCircle/Sources/App/CareCircleApp.swift`
  - Add `.onChange(of: scenePhase)` hook (or `.task(id:)`) on
    `RootView` to invoke `authState.verifyBackendSession()` when phase
    becomes `.active`.
- `CareCircle/Sources/Features/More/MoreView.swift`
  - Add a "Session" row inside the existing "Backend sync" section
    sourced from `authState.lastVerifiedProfile`.
- All view files listed in §End state #1 — one line each:
  `syncEngine.enqueueX(value)` after `modelContext.save()`.

## Wire-format reference (backend audit, condensed)

| operationType            | payload fields (camelCase JSON)                                                                                                         | backend route that will eventually consume |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `create_activity`        | already shipped — Phase 14                                                                                                              | `POST /v1/sync/batch` queue                |
| `create_medication`      | `medicationId, name, dosage, form, status, schedule, startDate?, endDate?, instructions?, colorHex?, fdaIngredients[]`                  | worker → `medications` insert              |
| `mark_dose_taken`        | `doseId, medicationId, takenAt, markedByAppleUserID?, notes?`                                                                           | worker → `dose_events` update              |
| `mark_dose_skipped`      | `doseId, medicationId, skippedAt, markedByAppleUserID?, notes?`                                                                         | worker → `dose_events` update              |
| `create_appointment`     | `appointmentId, title, provider?, location?, startsAt, durationMinutes, prepNotes?, reminderOffsetsMinutes[], createdByAppleUserID`     | worker → `appointments` insert             |
| `create_member`          | `memberId, appleUserID, displayName, role, status, joinedAt, invitedAt?, invitedByAppleUserID?, inviteShareURLString?`                  | worker → `members` insert                  |
| `create_emergency_contact` | `contactId, name, relationship?, phoneE164, isPrimary, isMedical, sortOrder`                                                          | worker → `emergency_contacts` insert       |
| `create_care_minute_entry` | `entryId, caregiverAppleUserID, caregiverDisplayName, serviceCode, serviceDescription, startedAt, endedAt, notes?, milesDriven?, fiscalIntermediary?` | worker → `care_minutes` insert     |
| `create_sos_event`       | `eventId, triggeredByAppleUserID, triggeredByDisplayName, triggeredAt, latitude?, longitude?, locationAccuracyMeters?`                  | worker → `sos_events` insert               |
| `create_document`        | `documentId, title, type, mimeType, sizeBytes, issuedAt?, expiresAt?, visibilityRoles[], uploadedByAppleUserID, uploadedByDisplayName`  | worker → `documents` insert (blob later)   |

The backend `/v1/sync/batch` endpoint accepts arbitrary
`operationType` strings and JSON payloads — validation will happen
when a worker job is later wired up to drain `pending_operations`.
Until then these are durably queued server-side and form the contract
we'll backfill from.

## Risks / decisions

- **No worker yet.** The backend stores ops but no job consumes them.
  Acceptable for this phase: it proves the iOS write path works and
  preserves the queue for when the worker arrives. The
  `client_op_id` UUID guarantees we won't double-apply on the future
  drain.
- **`create_member` semantics.** Member rows are created from two
  paths today: an explicit invite (AddMemberView) and an implicit
  CKShare acceptance. Phase 15 only hooks the explicit invite path —
  the CKShare path is harder because it happens deep inside the
  CloudKit acceptance handler. Note in the plan, revisit Phase 16.
- **Document blob.** This phase mirrors the row, not the bytes.
  Backend will see a `documents` row with `objectKey = null`. Phase
  17 introduces the presign flow and patches the key in.
- **Dose mark.** Marking a dose taken in the UI mutates an existing
  `DoseEvent` rather than inserting a new row. The op carries
  `doseId` so the backend worker can update by primary key when it
  exists.
- **`fetchMe()` latency.** A 200–600ms round-trip on launch is
  acceptable; the call doesn't block UI and runs in a `Task` from
  bootstrap. Failures don't sign the user out — they just clear
  `lastVerifiedProfile`.

## Definition of Done (checklist)

- [ ] 9 new payload types in `SyncOperation.swift`, all `nonisolated
      struct ...: Codable, Sendable, Equatable`.
- [ ] `SyncEngine` exposes 9 new `enqueue…` methods, each ≤5 lines via
      a shared private helper.
- [ ] `BackendAuthService.fetchMe()` exists; `AuthState` consumes it.
- [ ] `MoreView` shows session-verified status from the cached profile.
- [ ] All 8 listed write-site views call the matching `enqueue…` after
      `modelContext.save()`.
- [ ] `xcodebuild build` succeeds; swiftlint exits 0.
- [ ] One commit, conventional-commits message, no AI attribution.

## Open follow-ups (Phase 16+)

- Inbound sync: fetch state from backend at launch, hydrate SwiftData,
  reconcile against CloudKit.
- Document blob upload via MinIO presign (Phase 17).
- APNs registration via `POST /v1/me/devices` (Phase 18).
- WebSocket realtime tap on `/v1/realtime` (Phase 19).
- CKShare-acceptance path → `create_member` op (deferred from this
  phase).
