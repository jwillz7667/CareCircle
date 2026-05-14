# Phase 18 — Cross-device document key envelope + on-demand backend blob fetch + dose-event hydration

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 17 left two seams. First, member devices that didn't originate the
per-circle document DEK can't decrypt blobs that arrive via the Railway
backend's MinIO bucket. Second, the placeholder rows seeded by
`BackendHydrator.hydrateDocuments` show metadata only — there's no
fetch+decrypt path for the actual ciphertext. Phase 18 closes both, then
extends backend hydration to a third domain (medication dose events)
that has been live in the backend since Phase 13 but was never wired up
on iOS.

The DEK distribution piece uses `CKRecord.encryptedValues` for the per-
circle symmetric key. CloudKit handles end-to-end encryption of the
field across the share's invited participants — Apple's per-user key
machinery, not our problem. The DEK never appears in plaintext on a
server (the backend already only sees the ciphertext + the
backend-managed envelope key used for PHI fields like document titles).

## End state (definition of done)

1. New CloudKit record type `DocumentKeyEnvelope` (one per circle, in
   the per-circle shared zone):
   - `encryptedValues["dek"]: Data` — 32 raw bytes of the per-circle
     AES-256 symmetric key.
   - `recordName: "dek-envelope"` — predictable so members can fetch
     without enumeration.
2. New service `CircleDocumentKeySyncService` (`@MainActor`):
   - `publishIfNeeded(circleID:)` — owner-only. Reads the local
     Keychain DEK (provisioning if necessary) and writes the envelope
     record to `privateCloudDatabase` so the share automatically
     propagates it.
   - `pullIfMissing(circleID:)` — member-only. Fetches the envelope
     from `sharedCloudDatabase`, unwraps the encrypted DEK field, and
     stores it locally via `DocumentKeyStore`. No-op if the local key
     already exists.
3. New `BackendDocumentService.downloadCiphertext(documentId:)`:
   - `GET /v1/documents/:id/download-url` (already exists in backend).
   - Follow the presigned GET URL with `URLSession.data(from:)` and
     return `(ciphertext, nonce, tag)` as a `DocumentVault.SealedPayload`.
4. `DocumentDetailView` integrates the download path:
   - If `document.isBackendPlaceholder`, fetch ciphertext via the new
     service, build a `SealedPayload`, then decrypt with the existing
     `DocumentVault.open` path.
   - If the local DEK is missing, show the existing "Ask the Circle's
     primary caregiver to re-share" copy from `VaultError.keyUnavailable`.
5. `BackendHydrator.hydrate(forCircle:)` also hydrates dose events:
   - For each medication touched in the medications pass, fetch
     `GET /v1/medications/:id/doses` (existing endpoint).
   - Insert `DoseEvent` rows when the medication's local dose-event
     count is zero. Skip otherwise — local writes are authoritative
     once present.
6. App startup wires the key-sync service through:
   - `CareCircleApp` provisions the service into `.environment`.
   - `RootView.maybeHydrateOnce()` triggers `pullIfMissing` per circle
     after hydration completes.
   - `CircleSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`
     triggers `pullIfMissing` on share acceptance.
   - `AddDocumentView` triggers `publishIfNeeded` on first owner upload
     so the envelope arrives in CloudKit at the same time the first
     document does. Subsequent uploads skip the publish path (cached
     locally).

## Out of scope (deferred)

- DEK rotation. Same single per-circle key for the lifetime of the
  circle in v1. Rotation requires re-publishing the envelope and
  re-encrypting outstanding blobs; not needed for the family-scale
  threat model.
- Per-document keys. The whole circle shares one DEK.
- Background download prefetch. Blobs are pulled on detail-view open
  only; we don't bulk-download every backend placeholder eagerly.
- Backend-side dose-event mutations. The iOS app already writes dose
  events through the existing sync batch; Phase 18 only adds the
  *read* side.

## Architecture

```
Owner device (first upload after upgrade)
  AddDocumentView
    └─ DocumentVault.sealForOwner  (provisions DEK in Keychain)
    └─ CircleDocumentKeySyncService.publishIfNeeded
         └─ CKRecord(recordType: "DocumentKeyEnvelope",
                     recordID: dek-envelope in per-circle zone)
            encryptedValues["dek"] = 32 raw bytes
            privateDB.save(record) → CloudKit propagates to share

Member device (after accepting CKShare)
  CircleSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)
    └─ CircleSharingService.acceptShare
    └─ CircleDocumentKeySyncService.pullIfMissing
         └─ sharedDB.record(for: dek-envelope ID)
            DEK = record.encryptedValues["dek"]
            DocumentKeyStore.persist(dek, circleID:)

Member device (opening a backend-only placeholder)
  DocumentDetailView.decryptIfNeeded
    └─ if isBackendPlaceholder:
         └─ BackendDocumentService.downloadCiphertext
              └─ APIClient.send GET /v1/documents/:id/download-url
                 → {url, objectKey, encryptionNonce, encryptionTag}
              └─ URLSession.data(from: presigned url)
                 → ciphertext bytes
              └─ return SealedPayload(ciphertext, nonce, tag)
         └─ DocumentVault.open(payload:, circleID:)

BackendHydrator (one extra pass after medications)
  for each medication just hydrated:
    └─ APIClient.send GET /v1/medications/:id/doses
    └─ for each dto:
         if localCount(DoseEvent, medication) == 0:
           insert via makeDoseEvent mapper
```

## Wire-format notes

`GET /v1/documents/:id/download-url` (existing) returns:
```json
{ "url": "https://...minio...",
  "objectKey": "<circle>/2026-05-13/<hex>-<name>",
  "encryptionNonce": "<base64>",
  "encryptionTag": "<base64>" }
```
iOS already has the nonce + tag from hydration, but the backend
returns them again so the client doesn't have to round-trip a local
lookup. We use the returned values to stay tolerant of races.

`GET /v1/medications/:id/doses` (existing) returns:
```json
{ "doses": [ { "id": "...", "scheduledAt": "<ISO>", "takenAt": "<ISO|null>",
               "markedBy": "<uuid|null>", "status": "scheduled|taken|skipped|late",
               "notes": "<plaintext|null>" } ] }
```

## Risks and decisions

- **Why `CKRecord.encryptedValues` and not a raw `Data` field?**
  Shared zone records are protected by CloudKit's transport
  encryption and per-share access control, but `encryptedValues`
  layers Apple's end-to-end per-user key model on top. For a
  symmetric key payload that gates all document plaintext, the
  belt-and-suspenders is worth it.
- **Single record name (`dek-envelope`).** Predictability beats
  CRDT-style record enumeration. Race during share-accept is handled
  by retrying on missing record (member may fetch before the owner's
  zone has propagated).
- **No backend involvement.** Storing even a wrapped DEK on the
  backend would weaken the property that "only Circle members ever
  see plaintext" — Phase 17's whole point of E2EE for documents.
- **Dose event upper bound (200).** Matches the backend's hard cap.
  iOS hydrate inserts ≤ 200 most-recent doses per medication on cold
  start; subsequent doses arrive via the existing sync-batch +
  applicator path.

## Definition of done checklist

- [ ] `DocumentKeyEnvelope` CKRecord type defined + `CloudKitConfiguration`
      gains the constant.
- [ ] `CircleDocumentKeySyncService` implemented (publish + pull).
- [ ] `DocumentKeyStore` exposes a `persist(rawKey:circleID:)` writer
      so the sync service can save fetched envelopes.
- [ ] `BackendDocumentService.downloadCiphertext` works against the
      existing backend endpoint; returns a `SealedPayload`.
- [ ] `DocumentDetailView` decrypts backend-only placeholders without
      requiring a local CloudKit copy.
- [ ] `BackendHydrator.hydrate(forCircle:)` issues per-medication
      dose fetches and inserts DoseEvents when local is empty.
- [ ] `BackendHydratorMappers.makeDoseEvent(from:)` added.
- [ ] Backend read DTOs gain `MedicationDoseResponse` + `DoseDTO`.
- [ ] `AddDocumentView` triggers `publishIfNeeded` after the first
      owner-side upload completes.
- [ ] `CircleSceneDelegate` triggers `pullIfMissing` after share
      acceptance.
- [ ] `RootView.maybeHydrateOnce` triggers `pullIfMissing` for all
      circles on cold start (defense against share-accept happening
      before app launch).
- [ ] xcodebuild + swiftformat + swiftlint clean.
- [ ] Commit + push.

## Open follow-ups (Phase 19+ candidates)

- DEK rotation flow when a member is removed.
- Background `BGAppRefreshTask` to fetch missing blob ciphertext so
  documents don't block on first detail-view open.
- Backend-side dose event WebSocket fanout so member devices update
  without a hydrate pass.
