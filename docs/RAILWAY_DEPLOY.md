# Railway Deploy — CareCircle Backend

This is the operational runbook for deploying the CareCircle backend monorepo to Railway. The Node services run TypeScript directly via `tsx` — no compile step. Build phase only installs dependencies.

---

## Repository layout (what Railway sees)

```
/                         <- iOS app at repo root (Railway ignores)
backend/                  <- Railway services build from here
  railpack.json           <- defines install + start for the API service
  pnpm-workspace.yaml
  apps/
    api/                  <- HTTP + WebSocket service
    worker/               <- BullMQ job processor
    migrator/             <- one-shot SQL migrator + seed runner
  packages/
    db/                   <- schema, RLS helpers, drizzle client
    shared/               <- errors, logger, crypto, zod, hcbs
```

**Every Railway service must set Root Directory to `backend`.** This is required because pnpm workspace deps (`workspace:*`) only resolve from the workspace root.

---

## Services to provision

| Service | Type | Root dir | Start command (in Railway settings) | Public domain |
|---|---|---|---|---|
| `postgres` | Railway Postgres plugin | n/a | n/a | No |
| `redis` | Railway Redis plugin | n/a | n/a | No |
| `minio` | Docker image `minio/minio:latest` with `server /data --console-address :9001` | n/a | n/a | No |
| `api` | This repo, branch `main` | `backend` | *(default — uses `railpack.json`)* | Yes (`api.carecircle.app`) |
| `worker` | This repo, branch `main` | `backend` | `pnpm --filter @carecircle/worker start` | No |
| `migrator` | This repo, branch `main` | `backend` | `pnpm --filter @carecircle/migrator run migrate` | No (one-shot) |

The `api` service uses `railpack.json` directly — no overrides needed in Railway UI.

The `worker` and `migrator` services share the same repo and railpack but override the **Start Command** field in Railway service settings (Service → Settings → Deploy → Custom Start Command).

The `migrator` should be configured with **Restart Policy = Never** so it runs once per deploy and exits. Trigger seed data separately via a one-off command if needed (`pnpm --filter @carecircle/migrator run seed`).

---

## Environment variables

Set these on each service. Use Railway's **reference variables** (`${{ postgres.DATABASE_URL }}`) to share without copy-paste.

### Shared (all three node services)
```
NODE_ENV=production
LOG_LEVEL=info
DATABASE_URL=${{ postgres.DATABASE_URL }}
DIRECT_DATABASE_URL=${{ postgres.DATABASE_URL }}
REDIS_URL=${{ redis.REDIS_URL }}
MINIO_ENDPOINT=${{ minio.PRIVATE_DOMAIN }}
MINIO_PORT=9000
MINIO_USE_SSL=false
MINIO_ACCESS_KEY=<from minio root creds>
MINIO_SECRET_KEY=<from minio root creds>
MINIO_REGION=us-east-1
APP_MASTER_KEY=<32-byte random hex; generate with: openssl rand -hex 32>
```

### API-specific
```
HOST=0.0.0.0
PORT=${{ PORT }}                     # Railway injects this
JWT_SECRET=<32-byte random; openssl rand -hex 32>
JWT_KID=v1
JWT_ISSUER=carecircle-prod
JWT_AUDIENCE=carecircle.prod
APPLE_CLIENT_ID=Res.CareCircle
APPLE_ISSUER=https://appleid.apple.com
APPLE_VERIFIER_MODE=jwks             # NOT 'mock' in prod
APPLE_JWKS_URL=https://appleid.apple.com/auth/keys
RATE_LIMIT_PER_MIN=100
AUTH_RATE_LIMIT_PER_MIN=10
APNS_BUNDLE_ID=Res.CareCircle
APNS_MOCK_MODE=false                 # NOT 'true' in prod
APNS_TEAM_ID=487LC4H9U4
APNS_KEY_ID=<from Apple Developer portal>
APNS_PRIVATE_KEY=<the .p8 contents, base64-encoded>
```

### Worker-specific
Same as API minus the Fastify HTTP knobs (`HOST`, `PORT`, rate limits).
Add:
```
OPENAI_API_KEY=<for fallback LLM proxy>
OPENFDA_API_KEY=<optional>
```

### Migrator-specific
Only needs `DATABASE_URL`, `DIRECT_DATABASE_URL`, `APP_MASTER_KEY` (for `pgcrypto` smoke checks).

---

## Initial deploy

1. **Create Railway project** `carecircle-prod`. Add Postgres and Redis plugins.
2. **Add MinIO service**: New Service → Empty Service → Source → Image → `minio/minio:latest`. Set command to `server /data --console-address :9001`. Add a volume mounted at `/data` (50GB). Set env vars `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD`. Don't expose public.
3. **Connect this GitHub repo.** Create three services from the same repo:
   - `api` — Root Directory `backend`. Leave Build/Start commands empty (railpack.json handles it).
   - `worker` — Root Directory `backend`. Custom Start Command: `pnpm --filter @carecircle/worker start`.
   - `migrator` — Root Directory `backend`. Custom Start Command: `pnpm --filter @carecircle/migrator run migrate`. Restart Policy: Never.
4. **Fill env vars** per the tables above.
5. **First deploy: trigger `migrator` first.** It will create the schema (11 migrations applied in order, including the FORCE RLS on every PHI table). Confirm it exits cleanly with `Migration complete: 11 applied` in logs.
6. **Optionally trigger seed**: in Railway, run a one-off `pnpm --filter @carecircle/migrator run seed` against the migrator service to load demo data. **Skip this for real production.**
7. **Deploy `api` and `worker`.** They will start; `/v1/health` should return `{ "ok": true }` on the api domain.
8. **Custom domain:** Service → Settings → Networking → Add custom domain → `api.carecircle.app`. Point your DNS at the Railway CNAME.

---

## Why `tsx` instead of a compile step

The workspace packages (`@carecircle/db`, `@carecircle/shared`) expose `./src/index.ts` directly via their `package.json` `main` field. Compiling each package independently with `tsc` requires either project references or a bundler step. For an app of this size, running `tsx` in production is simpler:

- Cold start: +150ms vs compiled JS (negligible for a long-lived service)
- Memory: identical at steady state
- One less moving part: no `dist/` to invalidate, no source-map gymnastics
- `tsx` lives in each app's `dependencies` (not `devDependencies`) so production installs include it.

If cold start matters later (e.g., serverless), switch to `tsup` + a single bundled `dist/server.js`. The migration is mechanical.

---

## Health checks

Railway will hit the `api` service's port on `/`. The Fastify server registers `/v1/health` at start; set Health Check Path in service settings to `/v1/health` and Health Check Timeout to 30s.

The `worker` service has no HTTP server; disable health checks for it.

---

## Smoke test post-deploy

```bash
# Liveness
curl https://api.carecircle.app/v1/health

# Mint a mock SiwA token (requires APPLE_VERIFIER_MODE=mock — DO NOT use in prod;
# this is the staging path only).
# Real prod uses Apple's JWKS via the iOS client.

# List my circles (after iOS sign-in mints a real JWT)
curl https://api.carecircle.app/v1/circles -H "Authorization: Bearer <token>"
```

---

## Rolling back

Railway → service → Deployments → click any prior deployment → "Redeploy." Restores instantly. The database is unaffected by API rollback; rolling back a migration is a separate manual SQL operation (see `backend/packages/db/migrations/` for the forward migrations — there are no `down` migrations in v1; a rollback requires writing the inverse manually).

---

## Known gotchas

- **`pnpm install --frozen-lockfile` fails if a `package.json` was edited but `pnpm-lock.yaml` wasn't regenerated.** Always `pnpm install` locally and commit `pnpm-lock.yaml` before pushing.
- **MinIO endpoint over private network:** use `${{ minio.PRIVATE_DOMAIN }}`, not the public URL. Railway's private network bypasses egress charges.
- **Postgres connection limit:** Railway Postgres on the starter tier caps at ~22 concurrent connections. PgBouncer is in the spec but not yet provisioned; if you exceed limits, add it as a service (image `edoburu/pgbouncer:1.23.1`) and point `DATABASE_URL` at the pooler while `DIRECT_DATABASE_URL` keeps the direct connection for migrations.
- **CORS origin in prod:** set `CORS_ORIGIN` env var explicitly if the API is accessed from a web frontend. The iOS app uses URLSession and doesn't need CORS.
