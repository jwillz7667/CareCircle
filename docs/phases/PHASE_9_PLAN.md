# Phase 9 — Encrypted document vault (CryptoKit)

## Scope
Per spec §5.3 ("Documents are E2EE") and §3.4 (encryption strategy). Phase 9 ships:

- A new `Document` SwiftData model per Circle: type, title, encrypted ciphertext + nonce + tag, MIME type, byte size, optional expiry date, uploaded-by metadata, visibility roles, soft-delete timestamp.
- Per-circle 256-bit `SymmetricKey` held in iCloud Keychain (`kSecAttrSynchronizable`) so devices on the same iCloud account can decrypt. Key is generated on first use for the Circle owner; absent for joining members until the share flow (Phase 3+) propagates it.
- A `DocumentVault` service that wraps `AES.GCM.seal` / `AES.GCM.open` and stores only ciphertext on the model. Caller passes plaintext `Data`; service returns a sealed blob.
- A `DocumentKeyStore` that owns Keychain reads/writes for the circle key. Returns `.missing` when no key exists for the circle (so the UI can surface the "ask the owner to re-share" state).
- Add flow: PHPicker for photos, `.fileImporter` for PDFs/identifiers. Encrypt in-memory before write. Cap 10 MB; reject larger uploads with a clear message.
- List view grouped by document type, role-visibility filtered.
- Detail view: decrypt on view (in-memory only), show preview (image or PDF via `QuickLook`), expose share / delete actions. Re-encrypt is unnecessary — we never edit a document's bytes once stored.
- Disclaimer footers: documents containing prescription details fall under spec §5.6 only when surfacing medication data; no blanket disclaimer here.

Multi-device key propagation across non-iCloud accounts (e.g., share recipients) is deferred to Phase 3.5 (CKShare key sealing) and intentionally out of scope here. v1 design assumes circle members share the iCloud account boundary (same family Apple ID account family, iCloud Family Sharing, or one user manages and re-issues).

## Hard constraints
- No Xcode UI edits. New `.swift` files auto-include via the synchronized root.
- Keychain access via `Security` framework directly (no SPM addition). Use a `nonisolated final class` wrapper since the `Security` C API is thread-safe.
- Ciphertext stored as `Data` on the `@Model`. SwiftData transparently uses CKAsset for large blobs, so up to 10 MB per document is fine.
- No force-unwraps. Keychain failures bubble as a typed `DocumentVaultError`.
- Decryption results are not persisted to disk. Hold plaintext in `@State` only for the duration of the detail view.

## Build sequence
1. `DocumentType.swift` enum + display metadata + system-image icons. Build.
2. `Document.swift` SwiftData model. Update `Circle.swift` inverse relationship. Build.
3. `DocumentKeyStore.swift` — Keychain wrapper, `loadKey(circleID:) -> SymmetricKey?`, `provisionKey(circleID:) -> SymmetricKey`, `forget(circleID:)`. Build.
4. `DocumentVault.swift` — typed errors, `seal(plaintext:circleID:) -> SealedPayload`, `open(payload:circleID:) -> Data`. Build.
5. `DocumentDraft.swift` scratchpad + validation. Build.
6. `DocumentRowView.swift`. Build.
7. `DocumentListView.swift` — grouped by type, role-visibility filter, floating add button. Build.
8. `AddDocumentView.swift` — PHPicker + `.fileImporter`, size guard, encrypt before save. Build.
9. `DocumentDetailView.swift` — decrypt-on-appear, image/PDF preview, share sheet, delete with confirmation. Build.
10. Add Documents NavLink under MoreView's "Your Circle" section. Build.
11. swiftformat + swiftlint. Clean.
12. Commit + push.

## Data model sketch
```swift
@Model
final class Document {
    var id = UUID()
    var title = ""
    var typeRaw: String = DocumentType.other.rawValue
    var mimeType = "application/octet-stream"
    var sizeBytes = 0
    var ciphertext = Data()
    var nonce = Data()
    var tag = Data()
    var issuedAt: Date?
    var expiresAt: Date?
    var visibilityRolesRaw: [String] = MemberRole.allCases.map(\.rawValue)
    var uploadedByAppleUserID = ""
    var uploadedByDisplayName = ""
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?
    var circle: Circle?
}
```

## Keychain layout
- Service: `Res.CareCircle.documents`
- Account: `circle.<UUID>.key.v1`
- Accessible: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  - We deliberately use **device-only** in v1 because iCloud Keychain syncing of raw symmetric keys is not yet vetted by Apple's CryptoKit guidance. Devices that don't have the key see an "ask the Circle owner to re-share" state.
- Data: raw 32-byte key from `SymmetricKey(size: .bits256)`

Future enhancement (Phase 3.5): seal the SymmetricKey with each member's public CKShare key and propagate via record metadata.

## Visibility
A member sees a document only if their `MemberRole` is in `visibilityRolesRaw`. Defaults: all roles except `.viewOnly`. Owner can override on add.

## Validation
- Title required.
- `mimeType` whitelist: `image/jpeg`, `image/png`, `image/heic`, `application/pdf`.
- `sizeBytes` ≤ 10 MB (10 \* 1024 \* 1024).
- Either `ciphertext` and `nonce` and `tag` all present, or none (model invariant — soft-delete keeps the row but zeroes ciphertext).
