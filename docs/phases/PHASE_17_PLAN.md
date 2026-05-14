# Phase 17 — Document blob upload to MinIO via presigned PUT

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Documents are the only domain still trapped inside CloudKit. Phase 15
wired every other create through the Railway backend's sync batch, but
`create_document` was queued as metadata only — no blob, no object key,
no nonce or tag — because the encrypted payload still travels through
CloudKit as an inline `Data` field. Phase 17 closes that gap.

The iOS app already encrypts the document plaintext via
`DocumentVault` (AES-256-GCM with a per-circle `SymmetricKey` from the
Keychain). Phase 17 adds a three-step upload pipeline so that
ciphertext lands in MinIO and the metadata row lands in the `documents`
table — while local CloudKit storage continues to work unchanged for
in-family viewing.

Cross-device key distribution stays out of scope. A member device that
hasn't received the DEK still can't decrypt remote blobs; that ships in
Phase 18 alongside the CKShare-sealed key envelope.

## End state (definition of done)

1. A new `BackendDocumentService` in `Services/Backend/` that
   orchestrates the three-step upload:
   - `POST /v1/circles/:circleId/documents/upload-url` → presigned PUT
     URL for the `cc-documents` bucket.
   - `PUT` ciphertext bytes to the returned URL (no auth header,
     `Content-Type` matches the request).
   - `POST /v1/circles/:circleId/documents` with `objectKey`,
     `encryptionNonce`, `encryptionTag`, and the rest of the metadata.
2. New `Document.backendObjectKey: String?` field. `nil` means the
   document has not been mirrored to the backend yet; non-`nil` means
   the blob lives in MinIO under that key.
3. `AddDocumentView.save()` calls the uploader after the local
   SwiftData insert. Failure is non-fatal — the local document is
   already saved and CloudKit will still propagate it.
4. A `BackendDocumentRetrySweeper` that, on app foreground and after
   `lastVerifiedProfile` resolves, finds local documents with
   non-empty ciphertext and `backendObjectKey == nil` and retries the
   upload pipeline for the owner device.
5. `BackendHydrator` gains a `fetchDocuments(circleId:)` step that
   inserts placeholder rows locally when the local store has zero
   documents for that circle. Placeholders carry the
   `backendObjectKey` but empty `ciphertext/nonce/tag`. They show in
   the list with a "Backend only" badge until/unless the device has
   the DEK and pulls the blob (Phase 18+).
6. The legacy `create_document` sync-batch op type is removed —
   `SyncOperationType.createDocument`, `CreateDocumentPayload`, and
   `SyncEngine.enqueueDocumentCreate` go away. `AddDocumentView`
   switches to `BackendDocumentService.upload` directly.
7. `xcodebuild` succeeds on iPhone 16 Pro Max simulator; swiftlint
   exits 0 with no new errors.
8. No regression: existing CloudKit document flow still works
   end-to-end; non-owner devices still see the
   "Ask the primary caregiver to re-share" message when they try to
   add a document without the DEK.

## Out of scope (explicitly deferred)

- **Cross-device key distribution.** Phase 18 (CKShare-sealed key
  envelopes). Until then, only the owner device produces backend-
  visible documents.
- **Member-device upload.** Without the DEK the member can't seal a
  document, so there's nothing to upload. UI keeps the existing
  "Awaiting re-share" copy.
- **On-demand download for hydrated placeholders.** Phase 18 wires up
  `GET /v1/documents/:id/download-url` once members can decrypt.
- **Document deletes mirrored to the backend.** Local soft-delete via
  `deletedAt` already exists; backend `DELETE /v1/documents/:id`
  ships when we tackle authoring-history reconciliation.
- **Sync batch worker.** Backend `pending_operations` rows still
  accumulate without a worker. That's a separate phase.

## Architecture

```
AddDocumentView.save()
  └─► DocumentVault.sealForOwner(plaintext:circleID:)         (existing)
        ↓
        SwiftData insert + save                               (existing)
        ↓
        BackendDocumentService.upload(document:)              (new)
          ├─► POST /v1/circles/:id/documents/upload-url
          │     → { objectKey, url }
          ├─► PUT  url  ⟵ ciphertext bytes
          └─► POST /v1/circles/:id/documents
                → 201 { id }
        ↓
        document.backendObjectKey = objectKey

RootView.onAppear / scenePhase=.active
  └─► BackendDocumentRetrySweeper.sweep(modelContext:)
        ↓
        for each Document where backendObjectKey == nil
                              && !ciphertext.isEmpty
                              && deletedAt == nil:
          BackendDocumentService.upload(document:)
```

`BackendDocumentService` is an `actor` (it holds short-lived URLs and
co-operates with `APIClient`'s actor isolation). The sweeper is
`@MainActor` because it touches SwiftData.

## Files to create

- `CareCircle/Sources/Services/Backend/BackendDocumentService.swift`
  — three-step orchestrator.
- `CareCircle/Sources/Services/Backend/BackendDocumentRetrySweeper.swift`
  — `@MainActor` retry pass for documents not yet mirrored.

## Files to modify

- `CareCircle/Sources/Models/Document.swift` — add
  `backendObjectKey: String?` (optional + default `nil` so existing
  CloudKit rows migrate cleanly).
- `CareCircle/Sources/Services/Backend/BackendReadDTOs.swift` — add
  `DocumentsResponse` + `DocumentDTO` (`id, title, documentType,
  objectKey, mimeType, sizeBytes, issuedAt, expiresAt, uploadedBy,
  createdAt`).
- `CareCircle/Sources/Services/Backend/BackendHydrator.swift` — add
  the documents fetch + cold-start gate.
- `CareCircle/Sources/Services/Backend/BackendHydratorMappers.swift` —
  add `makeDocumentPlaceholder(from:)`.
- `CareCircle/Sources/Services/Backend/SyncOperation.swift` — drop
  `createDocument` + `CreateDocumentPayload`.
- `CareCircle/Sources/Services/Backend/SyncEngine.swift` — drop
  `enqueueDocumentCreate`.
- `CareCircle/Sources/App/CareCircleApp.swift` — instantiate
  `BackendDocumentService` and the sweeper, expose via environment.
- `CareCircle/Sources/App/RootView.swift` — call the sweeper alongside
  the existing hydrator on `.task`, `.onChange` of verified profile,
  and scenePhase active.
- `CareCircle/Sources/Features/Documents/AddDocumentView.swift` —
  replace `syncEngine.enqueueDocumentCreate(document)` with an
  awaited `BackendDocumentService.upload(...)` call. Don't block the
  dismiss; surface failure inline only if it's fast.
- `CareCircle/Sources/Features/Documents/DocumentRowView.swift` —
  show a "Backend only" badge for `backendObjectKey != nil && ciphertext.isEmpty`.
- `CareCircle/Sources/Features/More/MoreView.swift` — add a "Pending
  document uploads" diagnostic LabeledContent in Backend sync section.

## Wire-format expectations

| route                                         | request                                                                                                     | response                                                                 |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `POST /v1/circles/:id/documents/upload-url`   | `{ bucket: "cc-documents", contentType, sizeBytes, filename }`                                              | `{ bucket, objectKey, url, expiresInSeconds }`                           |
| `PUT  <presigned url>`                        | raw ciphertext bytes; `Content-Type` must match the request; no `Authorization` header                       | 200 OK                                                                   |
| `POST /v1/circles/:id/documents`              | `{ title, documentType, objectKey, mimeType, sizeBytes, encryptionNonce (b64), encryptionTag (b64), issuedAt?, expiresAt?, visibility? }` | `{ id }`                                                                 |
| `GET  /v1/circles/:id/documents`              | —                                                                                                           | `{ documents: [{ id, title, documentType, objectKey, mimeType, sizeBytes, issuedAt, expiresAt, uploadedBy, createdAt }] }` |

`encryptionNonce` and `encryptionTag` are base64-encoded —
`AES.GCM.Nonce` is 12 bytes, the tag is 16 bytes, so they fit
comfortably under the schema's `min(1)` constraint. `issuedAt`/
`expiresAt` are `YYYY-MM-DD` strings (UTC) per the existing
`createDocumentSchema` regex.

## Risks / decisions

- **Upload happens after local save, not before.** If the network
  drops mid-save, the user still has their document locally — and
  the retry sweeper will pick it up later. This matches Phase 15's
  "local first, backend best-effort" stance.
- **Presigned URL TTL is 300s.** Building the PUT and the metadata
  POST on top of a single in-memory presign keeps us inside that
  window. We don't persist the URL anywhere.
- **`URLSession.upload(for:from:)` over `upload(for:fromFile:)`.**
  The ciphertext is already in memory (`document.ciphertext`); writing
  it to disk just to upload would be wasted I/O. 10 MB cap stays
  enforced by `DocumentDraft.maxSizeBytes` upstream.
- **No `Authorization` header on the PUT.** The presigned URL carries
  the signature in its query string. Adding `Authorization: Bearer …`
  confuses MinIO's signature check.
- **Backend `visibility` defaults to all four roles** when omitted,
  matching `DocumentVisibility.defaultRoles`. We send the explicit
  set anyway so member-driven changes still mirror correctly.
- **`Document.backendObjectKey` is a soft flag, not a unique key.**
  We deliberately don't enforce uniqueness — duplicate uploads (e.g.,
  the same blob retried after a server-side timeout) cost us a stray
  MinIO object, not a data-integrity bug.
- **CKShare members see "Backend only" placeholders.** Until Phase 18
  distributes the DEK, hydrated documents aren't decryptable. The
  badge prevents users from tapping a row and getting a cryptic
  error — they see the title + type + dates but not the blob.

## Definition of Done (checklist)

- [ ] `BackendDocumentService` + `BackendDocumentRetrySweeper` files
      exist.
- [ ] `Document.backendObjectKey` added; existing rows migrate to
      `nil` without crashing.
- [ ] `BackendHydrator` hydrates document metadata when local is
      empty.
- [ ] Legacy `create_document` sync-batch op removed (SyncOperation,
      SyncEngine, AddDocumentView).
- [ ] `xcodebuild build` succeeds; swiftlint exits 0.
- [ ] One commit, conventional-commits message, no AI attribution.

## Open follow-ups (Phase 18+)

- CKShare-sealed key envelope so member devices receive the per-circle
  DEK.
- On-demand blob download via `GET /v1/documents/:id/download-url`.
- Backend-mirrored document soft-deletes (`DELETE /v1/documents/:id`).
- Row-level merge for any other domain (still open from Phase 16).
- Realtime WebSocket tap on `/v1/realtime`.
- Per-medication dose-event hydration.
