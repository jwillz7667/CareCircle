# Phase 13 — Railway-Postgres backend (full stack)

**Status:** in progress
**Started:** 2026-05-13
**Scope expansion:** Driven by user directive — "create the full
database and seed data and test all of it so it is fully functional".
This pulls v3-scoped backend work forward into v1.

## What this is

The CloudKit-only v1 iOS app already ships. This phase builds the
Railway-Postgres backend documented in `docs/CARECIRCLE_DATABASE_SPEC.md`
end-to-end, locally verifiable: PostgreSQL 16 + Fastify API + worker +
Redis + MinIO, all running under `docker compose up`.

## End state (definition of done)

- `backend/` monorepo: pnpm workspaces, strict TypeScript, no `any`.
- `docker compose up -d` brings up Postgres + Redis + MinIO + PgBouncer.
- `pnpm migrate` applies the schema cleanly into a fresh database, with
  RLS forced on every PHI table, audit triggers on every PHI table,
  NOTIFY triggers wired for realtime, and a member-cap trigger.
- `pnpm seed` populates two complete demo circles with multi-role
  membership and realistic activities, medications, appointments,
  shifts, documents (E2EE), emergency contacts, SOS events, and care
  minute entries.
- `pnpm test` runs Vitest against a disposable database:
  - RLS cross-circle isolation tests for every PHI table.
  - Sign in with Apple flow (Apple JWT verification mocked at the JWKS
    boundary so we can craft test tokens).
  - End-to-end auth → create circle → invite → activity feed → med
    dose → appointment → care minute roundtrip.
  - Member cap trigger.
  - Audit log immutability (UPDATE / DELETE rejected for app_user).
- `pnpm dev` boots the API on `:8080` and the worker on the same
  Compose network.
- `curl http://localhost:8080/v1/health` returns 200.
- All ~25 endpoints from spec §5.5 implemented.
- WebSocket `/v1/realtime` broadcasts row-change notifications from
  Postgres LISTEN → connected circle members.
- A `docs/BACKEND.md` runbook explains local boot, test, deploy.

## Out of scope (call-out)

- **APNs delivery**: the worker job is implemented and queueable, but
  sending requires a real APNs `.p8` key. Code path uses environment
  variables that are unset in local; the job no-ops and logs.
- **Real OpenAI / openFDA**: openFDA hits the public endpoint (no key
  required). OpenAI is wired but only runs when `OPENAI_API_KEY` is
  set; absence is not an error.
- **iOS client integration**: the SwiftData app keeps speaking
  CloudKit. Connecting it to this backend is Phase 14.
- **Railway deployment**: docker-compose proves the system. Railway
  service-by-service deploy is documented in `docs/BACKEND.md` but
  not executed (requires Railway dashboard).
- **HIPAA BAA**: documented, not enacted.

## Repo layout

```
backend/
  package.json                  # workspace root
  pnpm-workspace.yaml
  tsconfig.base.json
  docker-compose.yml
  .env.example
  docs/BACKEND.md
  packages/
    db/                         # Drizzle schema + SQL migrations + RLS
      package.json
      drizzle.config.ts
      src/
        schema.ts               # Drizzle TS schema (mirrors SQL)
        client.ts               # pg + Drizzle client factory
        rls.ts                  # SET LOCAL helpers
        index.ts
      migrations/
        0001_initial.sql        # everything from spec §4
        0002_notify_triggers.sql
    shared/
      package.json
      src/
        errors.ts               # typed error hierarchy
        zod.ts                  # cross-package Zod schemas
        crypto.ts               # AES-GCM (worker) + key wrap
        logger.ts               # pino + PHI redaction
        index.ts
  apps/
    api/
      package.json
      src/
        server.ts               # entrypoint
        app.ts                  # fastify wiring
        config.ts               # env validation (zod)
        middleware/
          auth.ts               # Bearer → req.user
          rls-context.ts        # SET LOCAL per tx
          error-handler.ts
        features/
          auth/                 # SiwA verify, refresh, logout
          me/
          circles/
          members/
          invitations/
          activities/
          medications/
          appointments/
          shifts/
          documents/
          emergency-contacts/
          sos/
          care-minutes/
          sync/
          realtime/             # WS
        services/
          apple-jwt.ts          # JWKS fetcher
          minio.ts              # signed URL issuance
          notify-listener.ts    # pg LISTEN
        domain/                 # pure types, no fastify import
        test/
          helpers.ts            # disposable schema, mint tokens
          rls.test.ts           # cross-circle isolation matrix
          auth.test.ts
          flow.test.ts          # end-to-end happy path
    worker/
      package.json
      src/
        worker.ts
        queues.ts
        jobs/
          push.ts
          openfda.ts
          openai.ts
          pdf-care-minutes.ts
    migrator/
      package.json
      src/
        migrate.ts              # applies SQL files in order
        seed.ts                 # demo data populator
```

## Build sequence

1. Monorepo scaffold + docker-compose + .env.example.
2. `packages/db`: Drizzle schema, SQL migrations from spec §4
   (extensions, roles, helpers, tables, RLS policies, audit triggers,
   updated_at trigger, member cap trigger, NOTIFY triggers).
3. Migrator app: applies SQL in order; `pnpm migrate` runs it.
4. `packages/shared`: errors, logger, crypto utilities.
5. API app: fastify bootstrap, auth middleware, RLS context,
   each feature endpoint group (auth → me → circles → members →
   invitations → activities → reactions → comments → medications →
   dose events → appointments → shifts → documents → emergency
   contacts → SOS → care minutes → sync batch → realtime).
6. Worker app: BullMQ queue registration; push, openFDA, OpenAI,
   PDF-generation jobs.
7. Seed: realistic demo data for two circles, encrypted via pgcrypto
   where the spec calls for it.
8. Tests: RLS matrix, auth flow, end-to-end, member cap, audit log
   immutability.
9. Live verification: `docker compose up`, migrate, seed, curl auth
   roundtrip, observe WS broadcast.
10. `docs/BACKEND.md` runbook.
11. Commit + push.

## Risks / decisions

- **Apple JWT in tests**: we cannot use real Apple-signed JWTs in
  tests. The JWKS fetcher is injected so tests can swap it for a
  local key pair; production reads `https://appleid.apple.com/auth/keys`.
- **MinIO signed URLs**: tests run against a real MinIO container,
  not mocked, so signed-URL roundtrip is exercised.
- **Audit log immutability**: enforced with role-level REVOKE
  UPDATE/DELETE plus a pgaudit-friendly schema. Tested.
- **`SET LOCAL` correctness**: tested by issuing two parallel
  transactions on the same pool and asserting context doesn't leak.

## Open follow-ups (Phase 14+)

- Wire the iOS SwiftData layer to this backend (replace CloudKit).
- Railway deploy (one project, multiple services).
- APNs production cert plumbing.
- pgBouncer in transaction mode for production scale (compose runs
  Postgres direct; PgBouncer container is present but optional).
