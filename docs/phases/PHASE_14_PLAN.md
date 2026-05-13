# Phase 14 — iOS ↔ Railway backend integration (shadow-sync slice)

**Status:** in progress
**Started:** 2026-05-13

## What this is

Phase 13 shipped the Railway backend (Postgres + Redis + MinIO + Fastify API
+ worker) but the iOS app still writes only through SwiftData + CloudKit.
Phase 14 connects the two so the backend becomes the **system of record**
for relational data — without disrupting the CloudKit-driven UX.

This phase ships a *vertical slice*: signed-in users mint a backend session
on top of their Apple sign-in, and one mutation surface (creating an
`Activity`) is mirrored to the backend through an idempotent op queue.
Adding more op types after this is a small repetition of the same pattern.

## End state (definition of done)

1. After Apple sign-in, the app also exchanges the identity token for a
   backend access + refresh token via `POST /v1/auth/apple`. Tokens live
   in the Keychain.
2. Hitting `/v1/me` with the access token returns 200 — verified at app
   launch.
3. Creating an `Activity` in the UI also queues a `PendingOperation`,
   which the new `SyncEngine` drains via `POST /v1/sync/batch`.
4. The More tab shows a small "Backend" footer: signed-in (✓), last sync
   time, and any recent error message.
5. App still launches and writes through CloudKit if the backend is
   unreachable. Backend errors are non-fatal; ops sit in the queue and
   retry with exponential backoff.
6. The build passes `xcodebuild` on iPhone 16 Pro Max simulator.

## Out of scope (call-out — explicitly deferred)

- **Read path** — pulling state down from the backend on launch. CloudKit
  remains authoritative for v1. Phase 15 handles the inbound sync.
- **WebSocket realtime** — CloudKit's `CKShare` push covers cross-device
  fan-out for now.
- **Other op types** — only `activity.create` is wired this phase.
  Medication, appointment, SOS, document, member, care-minute creates are
  Phase 15. Same pattern, just more handlers.
- **Document upload presigned URLs** — Phase 16.
- **APNs device registration** (`POST /v1/me/devices`) — depends on
  Apple Developer APNs key config; Phase 17.

## Architecture

```
SwiftData write site (e.g. ActivityComposerView.post())
  └─► CloudKit write (unchanged, current behavior)
  └─► SyncEngine.enqueue(.activityCreate(activity))
        └─► PendingOperation (SwiftData model) — opaque payload, clientOpId
              └─► SyncEngine.flush() — batch POST /v1/sync/batch
                    └─► On ack: delete the local PendingOperation
                    └─► On 401: APIClient refresh; retry once
                    └─► On 5xx / network: exponential backoff, persist
```

The `PendingOperation` model is a single SwiftData entity; no
`@Relationship`. Just `clientOpId UUID`, `operationType String`,
`payloadJSON Data`, `circleId UUID?`, `createdAt Date`, `lastAttemptAt
Date?`, `attemptCount Int`. Survives launches.

## Files to create

- `CareCircle/Sources/Services/Backend/APIClient.swift` — token-aware HTTP
  client. Owns the access/refresh token pair (held in `KeychainStore`),
  exposes `request(_:)` that injects `Authorization: Bearer …`, refreshes
  on 401, and surfaces typed errors.
- `CareCircle/Sources/Services/Backend/BackendAuthService.swift` — wraps
  `POST /v1/auth/apple`, `POST /v1/auth/refresh`, `POST /v1/auth/logout`.
  Called from `AuthState.completeAppleSignIn` after the local Apple flow.
- `CareCircle/Sources/Services/Backend/SyncEngine.swift` — `@Observable`,
  `@MainActor` queue manager. Reads `PendingOperation` from SwiftData,
  flushes in batches of 25, exposes `lastSyncedAt`, `pendingCount`,
  `lastError` for the UI footer.
- `CareCircle/Sources/Services/Backend/SyncOperation.swift` — value-type
  payload definitions (`ActivityCreatePayload`, …). Encoded into
  `PendingOperation.payloadJSON`.
- `CareCircle/Sources/Models/PendingOperation.swift` — SwiftData `@Model`
  for the durable client op queue.
- `CareCircle/Sources/Services/Backend/BackendConfiguration.swift` — reads
  `APIBaseURL` from `Info.plist` (default: Railway prod URL).

## Files to modify

- `CareCircle/Sources/App/CareCircleApp.swift` — add `PendingOperation` to
  the `Schema(...)` list, instantiate `APIClient` + `SyncEngine` and
  inject through `@Environment`.
- `CareCircle/Sources/Features/Auth/AuthState.swift` — after a successful
  Apple sign-in, also call `BackendAuthService.exchangeAppleIdentity(...)`.
  Failures here log + degrade gracefully; local Apple state is still
  considered signed-in.
- `CareCircle/Sources/Features/Auth/KeychainStore.swift` — add keys for
  `apiAccessToken`, `apiRefreshToken`, `apiAccessExpiresAt`.
- `CareCircle/Sources/Features/Activity/ActivityComposerView.swift` —
  after the SwiftData `modelContext.insert(activity)` + `try save()`,
  call `syncEngine.enqueueActivityCreate(activity)`.
- `CareCircle/Sources/Features/More/MoreView.swift` — append a "Backend"
  section showing connection state, last sync, pending count, last error.
- `CareCircle/Info.plist` — add `APIBaseURL` key
  (`https://carecircle-production-5669.up.railway.app`).

## Data model changes

```swift
@Model
final class PendingOperation {
    var id: UUID = UUID()
    var clientOpId: UUID = UUID()        // sent to server; stable on retry
    var operationType: String = ""       // e.g. "activity.create"
    var circleId: UUID?                  // server-side scoping
    var payloadJSON: Data = Data()
    var createdAt: Date = .now
    var lastAttemptAt: Date?
    var attemptCount: Int = 0
    var lastErrorMessage: String?

    init(clientOpId: UUID, operationType: String, circleId: UUID?, payloadJSON: Data) { ... }
}
```

No CloudKit `@Relationship` — this is a local-only queue; we don't want
it replicated to other devices.

## Public API surface added

```swift
// APIClient
public actor APIClient {
    public init(configuration: BackendConfiguration, keychain: KeychainStore)
    public func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
    public func storeTokens(_ tokens: BackendTokens) async
    public func clearTokens() async
    public var isAuthenticated: Bool { get async }
}

// BackendAuthService
@MainActor
public final class BackendAuthService {
    public init(client: APIClient)
    public func exchangeAppleIdentity(
        identityToken: String, nonce: String,
        givenName: String?, familyName: String?
    ) async throws
    public func refreshSession() async throws
    public func logout() async
}

// SyncEngine
@Observable @MainActor
public final class SyncEngine {
    public private(set) var lastSyncedAt: Date?
    public private(set) var pendingCount: Int = 0
    public private(set) var lastError: String?

    public init(client: APIClient, modelContext: ModelContext)
    public func enqueueActivityCreate(_ activity: Activity) async
    public func flush() async  // safe to call from .task / scenePhase change
}
```

## Risks / decisions

- **CloudKit + backend divergence.** Both writes happen; we accept the
  divergence for now. CloudKit is the read-source. Phase 15's inbound
  sync resolves this. Mitigation: payloads include `clientOpId` so the
  backend can deduplicate on its own pending-op idempotency key.
- **Token refresh races.** `APIClient` is an actor; only one refresh
  in flight at a time. If a refresh fails with 401/403, both tokens are
  cleared and `BackendAuthService` is asked to re-exchange.
- **Backend down at sign-in.** Local Apple sign-in still succeeds. The
  backend exchange is best-effort; the next `flush()` (called on
  scenePhase → active and after a Composer post) retries.
- **SwiftData schema migration.** Adding `PendingOperation` to the
  `Schema` is additive — SwiftData handles this without a manual
  migration. CloudKit-mirrored entities are unchanged.

## Definition of Done (checklist)

- [ ] `PendingOperation` model added to `Schema`; `ModelContainer` still
      initializes on a clean simulator.
- [ ] `APIClient` actor exists with token store + 401-retry path.
- [ ] `BackendAuthService.exchangeAppleIdentity(...)` called from
      `AuthState.completeAppleSignIn`; failures logged but not fatal.
- [ ] `SyncEngine` instance is injected via `@Environment`.
- [ ] `ActivityComposerView.post()` enqueues an `activity.create` op.
- [ ] `MoreView` shows a "Backend" section with status, last-sync,
      pending count, last error.
- [ ] `xcodebuild` succeeds on iPhone 16 Pro Max simulator.
- [ ] Manual smoke: sign in with the simulator's Apple ID, post an
      activity, see the "Backend" section update.

## Open follow-ups (Phase 15+)

- Inbound sync (read from backend on launch, hydrate SwiftData).
- Remaining op types: medication, appointment, SOS, member,
  emergency-contact, care-minute, document-create.
- APNs device registration once Apple Developer team uploads the
  APNs `.p8` key.
- WebSocket realtime tap on `/v1/realtime` for cross-device fan-out.
