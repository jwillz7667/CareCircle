# Phase 20 — Realtime WebSocket client + activity merge applicator

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 19 closed the loop on backend documents so the iOS app no longer
has to round-trip MinIO on every detail-view open. The remaining hole
in the hybrid sync model is reactivity: today, iOS only learns about
mutations made by another member by either (a) re-running
`BackendHydrator` cold-start logic (only inserts when local is empty)
or (b) refetching after a manual user interaction. There is no live
push.

The Railway backend already publishes per-row mutations onto
`pg_notify('circle_changes', …)` and fans them out via Fastify's
WebSocket at `GET /v1/realtime` (see `backend/apps/api/src/routes/realtime.ts`).
The wire protocol is small:

```json
{ "type": "subscribed", "circles": ["<uuid>", "<uuid>", …] }
{ "type": "change", "circleId": "<uuid>", "table": "activities",
  "rowId": "<uuid>", "op": "INSERT" | "UPDATE" | "DELETE" }
```

Phase 20 adds the iOS client end of that pipe and wires it through one
domain — activities — to prove the pattern. Other domains (medications,
dose events, appointments, members, care minutes, SOS, documents) keep
working through their existing cold-start hydration + manual-tap paths;
they get realtime applicators in Phase 21+.

Activities are the right starter domain: they're the highest-frequency
write surface (every voice note, photo, free-text post, reaction),
they're the most user-visible (the home feed updates while you watch),
and they're the simplest schema — no foreign-key fanout beyond the
already-hydrated `Member` rows.

## End state (definition of done)

1. New `BackendRealtimeClient` (`@Observable @MainActor` final class):
   - Holds a single `URLSessionWebSocketTask` to `wss://<host>/v1/realtime?token=<fresh>`.
   - `start(modelContext:)` connects and starts a receive loop. If
     already connected, no-op.
   - `stop()` cancels the task and clears any reconnect timer.
   - Exponential-backoff reconnect: 5s, 15s, 30s, 60s (capped). Reset
     on any successful frame. Bail out entirely on auth failure (4401).
   - Decodes incoming frames as a small enum `Frame.subscribed(circles:)`
     / `Frame.change(circleId:, table:, rowId:, op:)`.
   - Telemetry: `isConnected: Bool`, `lastConnectedAt: Date?`,
     `lastError: String?`, `subscribedCircleCount: Int`, `lastChangeAt: Date?`
     (read by `MoreView` debug surface).
2. `APIClient.freshAccessToken() async throws(APIError) -> String`
   public method. Internally delegates to the same plumbing
   `ensureFreshAccessToken()` uses; required because the WebSocket URL
   carries the token in the query string (backend accepts `?token=`).
3. Activity merge applicator on the realtime client:
   - When `change` frame arrives with `table == "activities"` (any op),
     fetch the first page of `/v1/circles/:id/activities?limit=20` for
     that `circleId`.
   - For each returned `ActivityDTO`, if `Activity(id == dto.id)` is
     not present locally and the circle exists locally, insert via
     `BackendHydratorMappers.makeActivity`.
   - `modelContext.save()` once at the end of the batch.
   - INSERTs are the realistic case for v1 (no UI for edits or hard
     deletes on activities). UPDATE/DELETE frames trigger the same
     refresh — the cap of 20 means we won't display anything stale; we
     just won't react to an edit beyond the most-recent page boundary
     until next foreground cold-start hydration.
4. Lifecycle wiring:
   - `CareCircleApp` provisions a `BackendRealtimeClient` (passes
     `APIClient` + `BackendConfiguration`), threads it via
     `.environment`.
   - `RootView.maybeHydrateOnce` calls `realtimeClient.start(modelContext:)`
     after `pullDocumentKeys()` + `triggerPrefetch`.
   - `RootView.onChange(scenePhase)`:
     - On `.active`: `start(modelContext:)` (idempotent).
     - On `.background` / `.inactive`: `stop()` so a phone sitting in
       a pocket doesn't drain battery on a persistent socket.
   - Sign-out path is already covered by the existing token clear —
     the next reconnect attempt 4401s out and the client bails.

## Out of scope (deferred to Phase 21+)

- Realtime applicators for medications / dose events / appointments /
  members / care minutes / SOS / documents. Each follows the activity
  applicator pattern but needs its own fetch path + mapper wiring.
- Soft-delete / hard-delete handling on activities. Backend supports
  it (the wire frame carries `op: "DELETE"`) but no iOS UI exists for
  it. When that lands, the applicator will need to honor the op.
- Snapshot-on-reconnect (replay missed frames). After a long
  background, the realtime stream picks up forward but doesn't backfill.
  Cold-start `BackendHydrator` already handles bootstrap; mid-session
  resyncs go through user-triggered refresh. Full backfill ledger
  (NOTIFY history table) is deferred.
- Auth-token refresh during an open socket. Access tokens have a 15-min
  expiry; in practice we'd reconnect after ≈ 15 minutes if the socket
  outlives the token. Phase 20's reconnect path handles that
  transparently — when the next 4401 arrives, we reconnect with a fresh
  token. A proper "rotate-in-place" flow is a Phase 22+ concern.
- Sending frames from iOS → backend. v1 is server-push only. Mutations
  still go through the existing `SyncEngine` HTTP path.

## Architecture

```
CareCircleApp
  └─ BackendRealtimeClient(apiClient:, configuration:)
  └─ .environment(realtimeClient)

RootView
  ├─ maybeHydrateOnce  (cold-start path)
  │    └─ … (Phase 18 + 19 unchanged) …
  │    └─ realtimeClient.start(modelContext:)         ← NEW
  └─ onChange(scenePhase)
       ├─ .active → realtimeClient.start(modelContext:)
       └─ .background → realtimeClient.stop()

BackendRealtimeClient.start
  ├─ guard !isConnected
  ├─ token = try await apiClient.freshAccessToken()
  ├─ url   = wss scheme of configuration.baseURL + /v1/realtime?token=<token>
  ├─ task  = urlSession.webSocketTask(with: url)
  ├─ task.resume()
  └─ receiveLoop()
       ├─ message = try await task.receive()
       ├─ decode JSON → Frame
       └─ dispatch:
            • .subscribed → record subscribedCircleCount + isConnected = true
            • .change(activities) → applyActivityChange(circleId:, modelContext:)
            • .change(otherTable) → log + ignore (Phase 21 will handle)
       └─ tail-call receiveLoop() until cancellation or error
            on error: scheduleReconnect()

scheduleReconnect()
  ├─ cancel any in-flight timer
  ├─ delay = min(60, baseDelay * 2^attempt)
  ├─ Task.sleep(nanoseconds: …)
  └─ start(modelContext:)

applyActivityChange(circleId:, modelContext:)
  ├─ guard local Circle(id == circleId) exists
  ├─ response: ActivitiesResponse =
  │    apiClient.send(GET /v1/circles/<id>/activities?limit=20)
  ├─ for each dto in response.activities:
  │    if !Activity exists with dto.id locally && dto.circleId matches:
  │      insert mapper.makeActivity(from: dto), set .circle = circle
  └─ modelContext.save()
```

## Risks and decisions

- **Why not piggy-back on `BackendHydrator`?** The hydrator's empty-
  domain gate is precisely the wrong behavior for incremental merge —
  it would no-op as soon as the local feed has ≥ 1 row. The applicator
  is a different code path with a row-level dedup gate.
- **Why fetch a page on every change frame instead of diffing the
  payload?** The frame intentionally carries no row contents (PHI
  isolation — pg_notify payload is bounded to 8KB and we don't want to
  leak PHI through it). A targeted fetch keeps the wire frame skinny
  and avoids server-side encryption logic for the notify path. Phase
  21 candidate: `GET /v1/activities/:id` for single-row refetch when
  the change frame carries a known row id, instead of paging.
- **Why activities only?** Each domain needs an idempotent insert
  mapper + a "fetch first page" REST shape. Activities have both
  already in place; medications/dose events have a per-medication
  fetch shape that's harder to drive from a single change frame
  (which only carries `rowId`, not parent). Phase 21 will introduce
  per-row fetch endpoints where needed.
- **Reconnect storm on backend restart.** Exponential backoff caps
  at 60s. Multiple iOS clients reconnecting at the same time after a
  Railway restart will spread over 60–120s; Fastify can absorb that.
- **Battery.** Persistent WebSocket on iOS over LTE is ≈ 1–2 mAh/hour
  when idle. Disconnecting on `.background` brings idle cost to zero.
  No `BGAppRefreshTask` reconnect — same Info.plist constraint as
  Phase 19's prefetch deferral.

## Wire format conversion

`BackendConfiguration.baseURL` is an HTTPS URL. The realtime endpoint
needs `wss://`. Conversion:

```swift
var components = URLComponents(url: configuration.baseURL,
                                resolvingAgainstBaseURL: false)!
components.scheme = components.scheme == "https" ? "wss" : "ws"
components.path = "/v1/realtime"
components.queryItems = [URLQueryItem(name: "token", value: token)]
let url = components.url!  // safe: built from valid baseURL
```

Production URL example: `https://carecircle-production-5669.up.railway.app/v1/realtime`
becomes `wss://carecircle-production-5669.up.railway.app/v1/realtime?token=<jwt>`.

## Definition of done checklist

- [ ] `APIClient.freshAccessToken()` public actor method.
- [ ] `BackendRealtimeClient` implemented:
      - URLSessionWebSocketTask connect + receive loop
      - Frame enum decode (subscribed + change)
      - Exponential reconnect (5/15/30/60s)
      - Idempotent start/stop
      - Telemetry fields
- [ ] `applyActivityChange(circleId:modelContext:)` fetches and
      idempotently inserts new activity rows.
- [ ] `CareCircleApp` provisions and exposes the client via
      `.environment`.
- [ ] `RootView` connects on cold-start + scenePhase `.active`;
      disconnects on `.background` / `.inactive`.
- [ ] xcodebuild + swiftformat + swiftlint clean.
- [ ] Commit + push.

## Open follow-ups (Phase 21+ candidates)

- Per-row REST fetch (`GET /v1/activities/:id`) so the applicator
  doesn't page on every change.
- Realtime applicators for medications, dose events, appointments,
  members, care minutes, SOS, documents.
- Snapshot-on-reconnect ledger for missed frames during long
  background.
- Auth-token rotate-in-place over an open socket.
- `BGAppRefreshTask` to keep the socket alive without a foreground.
