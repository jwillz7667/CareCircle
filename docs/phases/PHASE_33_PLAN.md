# Phase 33 — HealthKit vitals (manual-first, HK read skeleton)

## Goal

Add a Vitals domain to CareCircle so caregivers can record heart rate,
blood pressure, weight, blood glucose, SpO2, body temperature, and
respiratory rate against a Circle. Manual entry is the v1 path that
ships fully working. A HealthKit reader is built and wired in the same
phase, but it is **gated on the HealthKit entitlement** — until the user
adds the capability in Xcode (a single GUI step), the reader is a
runtime no-op.

The Vitals domain matches the cross-stack "new domain" template codified
in `docs/MASTER_PLAN_PHASES_30_34.md`: SwiftData `@Model` + Features
folder, backend table + routes + RLS, sync engine + hydrator +
realtime applicator. Phase 35 follow-up will add an `out-of-range`
pattern to the InsightsEngine that reads Vitals.

## Out of scope

- Phase 33 does **not** ship the InsightsEngine "vital out of range"
  detector. That is a Phase 35 task. The hooks are present (Vital owns a
  `recordedAt` + `valueNumeric` + `kind`) so the detector slots in
  cleanly.
- HealthKit *write* is out of scope. We only read from HK — caregivers
  add manual entries via the in-app form.
- No clinical-records (FHIR) HK toggle. Plain quantity types are enough
  for the v1 surface.
- Per-recipient reference ranges. Out-of-range checks (Phase 35) will
  use static clinical defaults (e.g. SpO2 < 90% is a warning).
- Charts and trends. v1 surfaces the most recent value per kind + a
  chronological list. Charts ship in a later polish phase.

## Trigger surface

- New entry in MoreView → "Vitals" (`heart.text.square` icon, between
  "Insights" and "Documents").
- VitalsListView lands on a chronological feed grouped by date with a
  per-kind summary header.
- Floating "Add reading" button presents `AddVitalView` as a sheet.
- Pull-to-refresh runs the realtime snapshot pass (same pattern as
  ShiftDigestListView).

## Files

New (iOS)

- `CareCircle/Sources/Models/VitalKind.swift` — `enum VitalKind` with
  raw values matching the backend's `vital_kind` enum (`heart_rate`,
  `blood_pressure_systolic`, `blood_pressure_diastolic`, `body_weight`,
  `blood_glucose`, `oxygen_saturation`, `body_temperature`,
  `respiratory_rate`). Carries `displayName`, `systemImage`,
  `canonicalUnit`, and `acceptedUnits` for UI rendering.
- `CareCircle/Sources/Models/VitalSource.swift` — `enum VitalSource`
  (`manual`, `healthkit`). Drives the row badge + filters.
- `CareCircle/Sources/Models/Vital.swift` — `@Model Vital` with
  `id`, `kindRaw`, `recordedAt`, `valueNumeric`, `valueText`, `unit`,
  `sourceRaw`, `healthkitUUID` (UUID), `notes`, `recordedByAppleUserID`,
  `recordedByDisplayName`, `createdAt`, `updatedAt`, `circle` back-ref.
- `CareCircle/Sources/Services/HealthKit/HealthKitVitalsReader.swift` —
  reader skeleton: detects HealthKit availability, requests
  authorization with the eight quantity types, queries the last 72h,
  upserts into SwiftData by `healthkitUUID`. Gated so calls become a
  no-op when the entitlement is missing.
- `CareCircle/Sources/Services/Backend/BackendRealtimeApplicatorsVitals.swift`
  — realtime applicator (`applyVitalChange`); list refetch, no
  delete-absent (50-row paginated window).
- `CareCircle/Sources/Features/Vitals/VitalsListView.swift` —
  chronological list + section headers + add CTA + pull-to-refresh.
- `CareCircle/Sources/Features/Vitals/VitalRowView.swift` — single
  reading row.
- `CareCircle/Sources/Features/Vitals/AddVitalView.swift` — add/edit
  form with kind picker + value field + unit picker + recorded-at +
  notes.
- `CareCircle/Sources/Features/Vitals/VitalSummaryHeader.swift` — most-
  recent value per kind, two-row grid above the list.

New (backend)

- `backend/packages/db/migrations/0013_vitals.sql` — `vitals` table +
  RLS + audit + notify trigger.
- `backend/apps/api/src/routes/vitals.ts` — POST (idempotent),
  GET list (cursor), GET by id, PATCH (author-only), DELETE
  (author soft-delete).
- `backend/apps/api/test/vitals.test.ts` — happy path, RLS, idempotency,
  HK upsert by `healthkit_uuid`.

Modified

- `backend/packages/shared/src/zod.ts` — `vitalKindSchema`,
  `vitalSourceSchema`, `createVitalSchema`, `updateVitalSchema`,
  `VitalKindT`, `VitalSourceT`.
- `backend/apps/api/src/app.ts` — register `vitalRoutes`.
- `CareCircle/Sources/App/CareCircleApp.swift` — add `Vital.self` to
  the SwiftData `Schema(...)`.
- `CareCircle/Sources/Models/Circle.swift` — add `vitalsStore` /
  `vitals` relationship.
- `CareCircle/Sources/Services/Backend/BackendReadDTOs.swift` —
  `VitalDTO`, `VitalsResponse`.
- `CareCircle/Sources/Services/Backend/BackendHydratorMappers.swift` —
  `makeVital(from:)` + `updateVital(_:from:)`.
- `CareCircle/Sources/Services/Backend/SyncEngine.swift` —
  `enqueueVitalCreate(_:)`.
- `CareCircle/Sources/Services/Backend/SyncOperation.swift` —
  `createVital` op type + `CreateVitalPayload`.
- `CareCircle/Sources/Services/Backend/BackendHydrator.swift` —
  `hydrateVitals(...)` + `circleScopedRowID` case for `Vital` +
  `vitalListPath(...)`.
- `CareCircle/Sources/Services/Backend/BackendRealtimeClient.swift` —
  dispatch `"vitals"` table to `applyVitalChange`.
- `CareCircle/Sources/Services/Backend/BackendRealtimeSnapshot.swift`
  — add `applyVitalChange` to the snapshot fan-out.
- `CareCircle/Sources/App/RootView.swift` — kick off
  `HealthKitVitalsReader.sync(...)` after backend hydration.
- `CareCircle/Sources/Features/More/MoreView.swift` — "Vitals" entry.

## Database schema (`vitals`)

```
id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4()
circle_id            UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE
recorded_by_user_id  UUID NOT NULL REFERENCES users(id)
kind                 TEXT NOT NULL                  -- matches VitalKind raw
recorded_at          TIMESTAMPTZ NOT NULL
value_numeric        NUMERIC(10, 3)                 -- nullable for free-text
value_text           TEXT                           -- e.g. "128/82" presentation
unit                 TEXT NOT NULL                  -- e.g. "bpm", "mmHg"
source               TEXT NOT NULL                  -- 'manual' | 'healthkit'
healthkit_uuid       UUID                           -- nullable; UNIQUE per circle
notes_enc            BYTEA                          -- envelope-encrypted notes
created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
deleted_at           TIMESTAMPTZ
version              BIGINT NOT NULL DEFAULT 1
client_op_id         UUID
```

Constraints:

- `vitals_kind_ck` — kind ∈ the eight raw values listed above.
- `vitals_source_ck` — source ∈ ('manual','healthkit').
- `vitals_value_ck` — at least one of `value_numeric` or `value_text`
  is non-null.

Indexes:

- `(circle_id, recorded_at DESC) WHERE deleted_at IS NULL`
- `(recorded_by_user_id)`
- `UNIQUE (circle_id, healthkit_uuid) WHERE healthkit_uuid IS NOT NULL`
  — the HK dedupe edge. Per-circle scope because the same HK row can
  legitimately appear across different test circles in dev.
- `UNIQUE (circle_id, client_op_id) WHERE client_op_id IS NOT NULL`

RLS / triggers follow the `shift_digests` template:

- `vitals_member_read` (SELECT, circle members)
- `vitals_member_write` (INSERT, member + recorded_by = current user)
- `vitals_author_update` / `vitals_author_delete`
- `set_updated_at` trigger
- `audit_trigger_fn` AFTER trigger
- `notify_circle_change` AFTER trigger

## Route surface

- `POST /v1/circles/:circleId/vitals` — body matches `createVitalSchema`.
  - Idempotency: replays via `clientOpId` *and* via `healthkitUUID`.
  - 201 `{ id, replayed }`.
- `GET /v1/circles/:circleId/vitals?cursor=…&limit=50` — DESC
  `(recorded_at, id)` cursor.
- `GET /v1/vitals/:id` — single read.
- `PATCH /v1/vitals/:id` — author-only updates value/unit/notes/
  recorded_at. Rejects kind change (a different kind is a different
  reading; the user should add a new row).
- `DELETE /v1/vitals/:id` — author-only soft-delete.

Returns DTO shape:

```jsonc
{
  "id": "…", "circleId": "…", "recordedByUserId": "…",
  "kind": "blood_pressure_systolic",
  "recordedAt": "2026-05-13T12:34:56.789Z",
  "valueNumeric": 128.0, "valueText": null,
  "unit": "mmHg", "source": "manual",
  "healthkitUuid": null, "notes": null,
  "createdAt": "…", "updatedAt": "…",
  "version": 1
}
```

## HealthKit gating

iOS Deployment Target is 17.0, so `HKHealthStore.isHealthDataAvailable()`
is always available. The HK reader uses **two** runtime gates:

1. `HKHealthStore.isHealthDataAvailable()` — false on iPad without
   HealthKit hardware support. Reader exits early.
2. Authorization status. The reader calls
   `requestAuthorization(toShare: [], read: <eight types>)`. When the
   entitlement is missing, the request throws or returns
   `.sharingDenied` for all types — reader treats that as a no-op.

The reader is registered through `RootView.maybeHydrateOnce()`. When
the entitlement is added later, the reader activates on next launch
with no code change.

## Xcode-UI step (single user action)

When the user wants to flip HealthKit on:

1. Open `CareCircle.xcodeproj`.
2. Target `CareCircle` → Signing & Capabilities → `+ Capability` →
   **HealthKit**.
3. Target `CareCircle` → Info → add two keys:
   - `NSHealthShareUsageDescription` = "CareCircle reads vitals from
     Health to add them to the active Circle's record."
   - `NSHealthUpdateUsageDescription` = "CareCircle does not write to
     Health; this key is required by the entitlement but unused."

`Info.plist` is in the build-settings membership exception list per
CLAUDE.md, so we add these via Xcode's Info tab — not via direct file
edits.

## Tradeoffs called out

- We deliberately keep BP as two rows (systolic + diastolic) rather
  than a single combined row. Simpler schema, charts work without
  custom rendering, and HealthKit emits the same way.
- `value_numeric` is `NUMERIC(10, 3)`. mmHg never exceeds 999, weight
  in lbs never exceeds 9999. We avoid `FLOAT` because the digit
  preservation matters when sharing a record-of-truth with future
  providers.
- The HK reader is per-launch only in v1. Background delivery
  (HKObserverQuery) is a known follow-up; running it in a Phase 33-only
  scope would balloon scope into background-mode work + entitlement
  changes.

## DOD checklist

- [ ] PHASE_33_PLAN.md committed (this file)
- [ ] `0013_vitals.sql` migration runs against a clean DB
- [ ] `vitalKindSchema` / `createVitalSchema` exposed from
      `@carecircle/shared`
- [ ] `vitalRoutes` registered in `app.ts`
- [ ] `pnpm test` clean (existing 68/68 + new vitals tests)
- [ ] `Vital`/`VitalKind`/`VitalSource` Swift models compile
- [ ] `Vital.self` added to `Schema` and `Circle.vitals` relationship
      compiles
- [ ] Sync layer wired: DTO + mapper + SyncEngine + Applicator +
      Hydrator
- [ ] Realtime: `BackendRealtimeClient.dispatch` routes `"vitals"` and
      `snapshotResync` calls `applyVitalChange`
- [ ] `HealthKitVitalsReader` skeleton compiles and is invoked from
      `RootView` after hydration
- [ ] Vitals UI: list/add/row/summary header reachable from MoreView
- [ ] Pull-to-refresh on VitalsListView calls `snapshotResync`
- [ ] `MedicationDisclaimerFooter` (or equivalent) on every Vital screen
- [ ] xcodebuild clean
- [ ] swiftformat + swiftlint clean on every touched file
- [ ] commit: `feat(ios+api): vitals domain — manual entry + HealthKit
      read skeleton (Phase 33)`
- [ ] push to origin/main

## Commit message

`feat(ios+api): vitals domain — manual entry + HealthKit read skeleton (Phase 33)`
