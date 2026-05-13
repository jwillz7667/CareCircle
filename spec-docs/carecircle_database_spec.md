# CareCircle — Database & Backend Architecture Specification

**Version:** 1.0 (Railway-native)
**Last updated:** May 13, 2026
**Deployment target:** Railway (single project, multiple services)
**Status:** Recommended architecture, ready to build
**Companion docs:** `CARECIRCLE_SPEC.md` (product spec), `carecircle_claude_code_prompt.md` (build prompt)

---

## 0. Architectural decision and rationale

**Stack: Railway-hosted Postgres 16 + Node.js (Fastify) API + Redis + MinIO object storage. No Supabase, no third-party BaaS.**

### Why this stack

CareCircle's core data shape — shared family circles with real-time activity feeds, sensitive health information, photo/voice/PDF storage, and a need to keep all options open for an eventual HIPAA-bearing B2B path — demands a real backend, not a thin SDK layer. Going Railway-native (instead of dropping Supabase on top) gives you:

1. **Full ownership of the auth path.** Sign in with Apple verification happens in your code. No vendor-defined user table. No magic. You know exactly what's in the JWT and how it's checked.
2. **Surgical RLS policies.** Postgres Row-Level Security is doing the heavy lifting for multi-tenant data isolation. You define the policies, you understand every one of them, and they can't be bypassed by a client SDK bug.
3. **One platform, one bill.** App + database + storage + cache + workers all on Railway, all on the same private network. No cross-cloud egress fees, no cross-vendor latency.
4. **HIPAA-ready path.** Railway offers a Business Associate Agreement as an add-on, accessed at trust.railway.com. When a BAA is in effect, Railway team members can no longer directly access running workloads — a strong technical control. Same BAA covers Postgres, your Node API, MinIO, and Redis as long as they all live in one Railway project.
5. **No vendor lock-in.** Standard Postgres. Standard Node. Standard S3 API. If you ever need to leave Railway, `pg_dump` and `aws s3 sync` and you're out.
6. **Justin's existing skill match.** You've already built Next.js + Postgres apps (DankDeals), and Railway services (MyAutoWhiz). This is a continuation, not a context switch.

### What you give up

- **No managed auth.** You build the Sign in with Apple JWT verification flow yourself (small file, well-documented pattern).
- **No auto-generated REST API.** You write API endpoints by hand — or use PostgREST as an opt-in layer for simple CRUD. (Recommendation below: skip PostgREST in v1; write the endpoints.)
- **No drag-and-drop dashboard.** You manage Postgres via `psql`, Railway's web console, and a tool like TablePlus or DataGrip locally.

The tradeoff is favorable. CareCircle needs ~25 API endpoints in v1, not 250 — the boilerplate cost of building them is low, and the control benefit is high.

---

## 1. System architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          iOS Device(s)                               │
│                                                                      │
│   ┌───────────────────────────────────────────────────────────────┐  │
│   │  CareCircle iOS app (SwiftUI + Swift 6)                       │  │
│   │                                                               │  │
│   │  ┌────────────┐  ┌──────────────┐  ┌────────────────────┐    │  │
│   │  │ SwiftData  │  │  Keychain    │  │  CryptoKit         │    │  │
│   │  │ local      │  │  refresh tok │  │  E2EE document     │    │  │
│   │  │ cache      │  │  + circle key│  │  envelope          │    │  │
│   │  └─────┬──────┘  └──────────────┘  └────────────────────┘    │  │
│   │        │                                                     │  │
│   │  ┌─────┴─────────────────────────────────────────────────┐   │  │
│   │  │  APIClient (URLSession + JWT) + WebSocketClient       │   │  │
│   │  │  + SyncEngine (operation queue, conflict resolver)    │   │  │
│   │  └────────────────────┬──────────────────────────────────┘   │  │
│   └────────────────────────┼─────────────────────────────────────┘  │
└────────────────────────────┼────────────────────────────────────────┘
                             │ HTTPS / TLS 1.3 / WSS
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Railway Project: carecircle-prod                    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Public-facing service (single domain)                       │    │
│  │  ┌────────────────────────────────────────────────────────┐  │    │
│  │  │  api.carecircle.app  (custom Railway domain)           │  │    │
│  │  │  ─────────────────────────────────────────────          │  │    │
│  │  │  Node.js 22 + Fastify + Socket.IO                      │  │    │
│  │  │  • POST /v1/auth/apple    (SiwA verification)          │  │    │
│  │  │  • POST /v1/auth/refresh                               │  │    │
│  │  │  • REST /v1/circles, /v1/activities, /v1/meds, …       │  │    │
│  │  │  • WS   /v1/realtime                                   │  │    │
│  │  │  • POST /v1/uploads/sign  (issues MinIO signed URL)    │  │    │
│  │  │  • RLS context: SET app.current_user_id per request    │  │    │
│  │  └─────────┬──────────────────────────┬───────────────────┘  │    │
│  └────────────┼──────────────────────────┼──────────────────────┘    │
│               │  private network only    │                           │
│      ┌────────┴────────┐         ┌───────┴───────┐                   │
│      ▼                 ▼         ▼               ▼                   │
│  ┌─────────────┐   ┌──────────┐ ┌──────────┐ ┌──────────────────┐    │
│  │ PostgreSQL  │   │  Redis   │ │  MinIO   │ │  Worker service  │    │
│  │ 16          │   │  7       │ │  (S3)    │ │  Node + BullMQ   │    │
│  │             │   │          │ │          │ │  • APNs fan-out  │    │
│  │  pgcrypto   │   │ • Cache  │ │ Buckets: │ │  • openFDA proxy │    │
│  │  pgaudit    │   │ • Pub/   │ │ • photos │ │  • OpenAI proxy  │    │
│  │  uuid-ossp  │   │   sub    │ │ • voice  │ │  • PDF gen       │    │
│  │             │   │ • Rate   │ │ • docs   │ │  • Audit roll-up │    │
│  │ Daily PITR  │   │   limit  │ │          │ │                  │    │
│  │ backups     │   │ • BullMQ │ │          │ │                  │    │
│  └─────────────┘   └──────────┘ └──────────┘ └──────────────────┘    │
│                                                                      │
│  Only api.carecircle.app has a public domain.                        │
│  Everything else is private-networking only.                         │
└──────────────────────────────────────────────────────────────────────┘
```

### Local-first principle

The iOS app reads and writes **SwiftData first, always**. Sync happens in the background. The user never waits for the network. This matches Apple's local-first pattern (Photos, Notes, Reminders).

Sync flow:
1. User taps "mark med as taken" → SwiftData write completes in <50 ms → UI updates instantly.
2. A `SyncEngine` actor enqueues the change to a local `pending_operations` table.
3. When network is available, the engine replays operations against the API.
4. WebSocket subscription pushes remote changes from other Circle members back; the engine writes them to SwiftData.
5. Conflict resolution policy: see §5.4.

**SwiftData is the local source of truth for the running app. Postgres is the durable source of truth across devices and time.**

---

## 2. Database choice and configuration

### 2.1 PostgreSQL 16 on Railway

Railway provisions PostgreSQL as a standard, unmanaged instance — you get a clean Postgres with the official Docker image. Railway has confirmed that features like Row-Level Security are not pre-enabled; you turn them on yourself.

Settings to configure on day one:

```sql
-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- column-level encryption
CREATE EXTENSION IF NOT EXISTS "pgaudit";     -- HIPAA-friendly audit logging
CREATE EXTENSION IF NOT EXISTS "citext";      -- case-insensitive text (emails)
CREATE EXTENSION IF NOT EXISTS "btree_gin";   -- composite indexes

-- Force TLS and strong password hashing in postgresql.conf:
-- ssl = on
-- ssl_min_protocol_version = 'TLSv1.2'
-- password_encryption = 'scram-sha-256'
-- pgaudit.log = 'write, ddl'   (don't log SELECT — too much noise and PHI risk)

-- Force RLS even for table owners (critical: Postgres owners bypass RLS by default).
-- We do this per-table with ALTER TABLE … FORCE ROW LEVEL SECURITY.
```

**Why this matters for healthcare:** Postgres table owners normally bypass RLS, which would defeat the whole purpose. Always issue `ALTER TABLE … FORCE ROW LEVEL SECURITY` on every PHI-bearing table. Confirmed by PostgreSQL official docs.

### 2.2 Connection pooling

Use **PgBouncer** (deployable on Railway as a side-service) in transaction-pooling mode. Fastify connects to PgBouncer, PgBouncer connects to Postgres. This lets you handle 200+ concurrent iOS clients on a $5–10/month Postgres instance.

Set `max_connections = 100` on Postgres; PgBouncer fans out to ~1000 client connections.

### 2.3 Sizing

| Component | MVP size | Notes |
|---|---|---|
| Postgres | 1 GB RAM, 1 vCPU, 10 GB disk | Handles ~1000 active circles comfortably |
| Redis | 256 MB | Sessions, pub/sub, BullMQ queues |
| MinIO | 50 GB initially | Photos and voice notes dominate; scales linearly |
| API service | 512 MB RAM, 1 vCPU | Fastify is light; 2 replicas behind Railway's load balancer |
| Worker service | 512 MB RAM, 1 vCPU | 1 replica; scale up only if push queue backs up |

Estimated monthly cost at 1000 active circles: $40–60 on Railway.

### 2.4 Backups and disaster recovery

- **Railway automated daily snapshots:** retained 7 days on standard tier, 30 days on Pro.
- **Logical backups:** a nightly `pg_dump` cron job in the worker service that uploads encrypted dumps to MinIO with 90-day retention.
- **Point-in-time recovery:** enable Railway's PITR if available on your tier.
- **Restore drill:** schedule a quarterly restore-into-staging exercise; document the runbook.

---

## 3. Schema design philosophy

### 3.1 Multi-tenancy via Circle isolation

Every PHI-bearing table has a `circle_id` foreign key. Every PHI-bearing table has an RLS policy keyed on `circle_id`. A user can only see rows for circles they are a member of. This is enforced *at the database*, not in the API. Even a totally broken API endpoint cannot leak data across circles.

### 3.2 Soft delete

PHI tables use `deleted_at TIMESTAMPTZ NULL` rather than hard deletes. This preserves audit trails (HIPAA requirement) and lets us recover from accidental deletions. A nightly purge job hard-deletes rows where `deleted_at < NOW() - INTERVAL '90 days'`.

### 3.3 Immutable audit log

Every write to a PHI table fires a trigger that writes to `audit_log`. The audit log is append-only — no UPDATE or DELETE permission for any application role. This is non-negotiable for HIPAA Security Rule §164.312(b).

### 3.4 Encryption strategy (three layers)

1. **At rest, disk level:** Railway uses encrypted volumes by default.
2. **At rest, column level:** Sensitive PHI fields (Care Recipient name, DOB, conditions, document contents) use `pgcrypto`'s `pgp_sym_encrypt` with a per-circle symmetric key. The circle key is stored in a separate `circle_keys` table, encrypted with the app's master key (held in Railway environment variables, never in the DB).
3. **End-to-end (documents only):** For Documents (advance directives, insurance cards), the iOS app encrypts the file with a circle-symmetric key from CryptoKit *before* uploading to MinIO. The server never sees plaintext. The key itself is propagated to other circle members via the API but never stored on the server in plaintext.

**Important pgcrypto caveat:** Encrypted columns cannot be indexed or queried with WHERE clauses on the encrypted content. We use encryption only for fields that are read by ID, never searched.

### 3.5 Naming conventions

- `snake_case` for all tables and columns
- Plural table names (`activities`, `medications`)
- `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()` on every table
- `created_at`, `updated_at`, `deleted_at` on every PHI table
- Foreign keys named `<other_table_singular>_id`
- Junction tables: `<table_a>_<table_b>` alphabetical

### 3.6 What NOT to put in the database

- Photos, voice recordings, PDFs → MinIO (database stores only the object key)
- Server-side session state → Redis
- Rate-limit counters → Redis
- Job queues → Redis (BullMQ)

---

## 4. Complete schema (SQL DDL)

```sql
-- =========================================================================
-- CareCircle Postgres Schema v1.0
-- Target: PostgreSQL 16 on Railway
-- All times stored in UTC; client displays in local timezone.
-- =========================================================================

-- ---------- 4.1 Application roles ----------

-- Anonymous role for pre-auth requests (sign-in endpoint only)
CREATE ROLE app_anon NOLOGIN;
GRANT USAGE ON SCHEMA public TO app_anon;

-- Authenticated role for normal API calls (RLS-restricted)
CREATE ROLE app_user NOLOGIN;
GRANT USAGE ON SCHEMA public TO app_user;

-- Service role for server-side jobs (worker service); BYPASSES RLS for admin tasks
CREATE ROLE app_service NOLOGIN BYPASSRLS;
GRANT USAGE ON SCHEMA public TO app_service;

-- ---------- 4.2 Helper functions ----------

-- The API sets these per request via:
--   SET LOCAL app.current_user_id = '...';
--   SET LOCAL app.current_circle_id = '...';
CREATE OR REPLACE FUNCTION current_user_id() RETURNS UUID AS $$
  SELECT COALESCE(current_setting('app.current_user_id', TRUE)::UUID, NULL);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION current_circle_id() RETURNS UUID AS $$
  SELECT COALESCE(current_setting('app.current_circle_id', TRUE)::UUID, NULL);
$$ LANGUAGE SQL STABLE;

-- Verify the current user is a member of a circle (used by RLS policies)
CREATE OR REPLACE FUNCTION is_circle_member(p_circle_id UUID) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = p_circle_id
      AND user_id   = current_user_id()
      AND deleted_at IS NULL
  );
$$ LANGUAGE SQL STABLE;

-- Verify the current user has a specific role in a circle
CREATE OR REPLACE FUNCTION circle_member_has_role(p_circle_id UUID, p_roles TEXT[])
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = p_circle_id
      AND user_id   = current_user_id()
      AND role      = ANY(p_roles)
      AND deleted_at IS NULL
  );
$$ LANGUAGE SQL STABLE;

-- ---------- 4.3 Audit log (append-only) ----------

CREATE TABLE audit_log (
    id           BIGSERIAL PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actor_id     UUID,
    circle_id    UUID,
    action       TEXT NOT NULL,           -- INSERT, UPDATE, DELETE, READ_SENSITIVE
    table_name   TEXT NOT NULL,
    row_id       UUID,
    diff         JSONB,                   -- {before: {...}, after: {...}}
    ip_address   INET,
    user_agent   TEXT
);

CREATE INDEX audit_log_circle_time_idx ON audit_log(circle_id, occurred_at DESC);
CREATE INDEX audit_log_actor_time_idx  ON audit_log(actor_id, occurred_at DESC);

-- app_user can INSERT but never UPDATE or DELETE
GRANT INSERT, SELECT ON audit_log TO app_user;
REVOKE UPDATE, DELETE ON audit_log FROM app_user;

-- ---------- 4.4 Users ----------

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_user_id       TEXT UNIQUE NOT NULL,        -- the `sub` from Apple JWT
    email               CITEXT UNIQUE,               -- may be Apple's relay; nullable
    is_private_email    BOOLEAN NOT NULL DEFAULT FALSE,
    display_name        TEXT,
    photo_object_key    TEXT,                        -- MinIO key, nullable
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX users_apple_id_idx ON users(apple_user_id);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

-- Users can see only their own row, plus minimal profile data for circle co-members
CREATE POLICY users_self ON users
  FOR SELECT TO app_user
  USING (id = current_user_id() OR EXISTS (
    SELECT 1 FROM circle_members cm1
    JOIN circle_members cm2 ON cm1.circle_id = cm2.circle_id
    WHERE cm1.user_id = current_user_id()
      AND cm2.user_id = users.id
      AND cm1.deleted_at IS NULL
      AND cm2.deleted_at IS NULL
  ));

CREATE POLICY users_update_self ON users
  FOR UPDATE TO app_user
  USING (id = current_user_id());

-- ---------- 4.5 Devices (for push notifications) ----------

CREATE TABLE devices (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    apns_token      TEXT NOT NULL,
    device_name     TEXT,
    os_version      TEXT,
    app_version     TEXT,
    locale          TEXT,
    timezone        TEXT,
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, apns_token)
);

CREATE INDEX devices_user_idx ON devices(user_id);
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;

CREATE POLICY devices_self ON devices FOR ALL TO app_user
  USING (user_id = current_user_id());

-- ---------- 4.6 Circles ----------

CREATE TYPE subscription_tier AS ENUM ('free', 'family', 'pro');
CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled', 'expired');

CREATE TABLE circles (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                     TEXT NOT NULL,                  -- "Mom's Care"
    owner_user_id            UUID NOT NULL REFERENCES users(id),
    care_recipient_id        UUID,                            -- FK added below after care_recipients exists
    subscription_tier        subscription_tier NOT NULL DEFAULT 'free',
    subscription_status      subscription_status NOT NULL DEFAULT 'active',
    subscription_renews_at   TIMESTAMPTZ,
    revenuecat_subscriber_id TEXT,
    settings                 JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ
);

CREATE INDEX circles_owner_idx ON circles(owner_user_id);
ALTER TABLE circles ENABLE ROW LEVEL SECURITY;
ALTER TABLE circles FORCE ROW LEVEL SECURITY;

CREATE POLICY circles_member_read ON circles FOR SELECT TO app_user
  USING (is_circle_member(id));

CREATE POLICY circles_owner_update ON circles FOR UPDATE TO app_user
  USING (owner_user_id = current_user_id());

CREATE POLICY circles_insert ON circles FOR INSERT TO app_user
  WITH CHECK (owner_user_id = current_user_id());

-- ---------- 4.7 Circle keys (envelope-encryption metadata) ----------

CREATE TABLE circle_keys (
    circle_id           UUID PRIMARY KEY REFERENCES circles(id) ON DELETE CASCADE,
    encrypted_dek       BYTEA NOT NULL,    -- circle data-encryption-key, wrapped by app master key
    key_version         INT NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_at          TIMESTAMPTZ
);

-- Only server-side service role can read these
GRANT SELECT, INSERT, UPDATE ON circle_keys TO app_service;
REVOKE ALL ON circle_keys FROM app_user, app_anon;

-- ---------- 4.8 Care Recipients ----------

CREATE TABLE care_recipients (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id               UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    -- Encrypted PHI fields (encrypted with circle key on app side)
    first_name_enc          BYTEA NOT NULL,
    last_name_enc           BYTEA,
    date_of_birth_enc       BYTEA,         -- encrypted; we don't query by DOB
    photo_object_key        TEXT,           -- MinIO key
    -- Non-PHI fields
    has_user_account        BOOLEAN NOT NULL DEFAULT FALSE,
    user_id                 UUID REFERENCES users(id),  -- if the senior signs in themselves
    primary_conditions_enc  BYTEA,          -- JSON array, encrypted
    pronouns                TEXT,           -- not considered PHI
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);

ALTER TABLE circles ADD CONSTRAINT circles_recipient_fk
  FOREIGN KEY (care_recipient_id) REFERENCES care_recipients(id);

CREATE INDEX care_recipients_circle_idx ON care_recipients(circle_id);
ALTER TABLE care_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_recipients FORCE ROW LEVEL SECURITY;

CREATE POLICY care_recipients_member ON care_recipients FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.9 Circle Members ----------

CREATE TYPE member_role AS ENUM (
  'owner',             -- the primary caregiver who created the circle
  'family_member',     -- siblings, cousins, etc.
  'paid_aide',         -- W-2 or contract aides
  'paid_family',       -- family caregiver paid via fiscal intermediary
  'care_recipient',    -- the senior themselves
  'view_only'          -- distant relative on read-only access
);

CREATE TYPE member_status AS ENUM ('invited', 'active', 'paused', 'removed');

CREATE TABLE circle_members (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role                member_role NOT NULL,
    status              member_status NOT NULL DEFAULT 'active',
    display_name        TEXT NOT NULL,     -- override for this circle ("Mom" instead of "Eleanor")
    permissions         JSONB NOT NULL DEFAULT '{}'::jsonb,
    notification_prefs  JSONB NOT NULL DEFAULT '{"push": true, "digest": "daily"}'::jsonb,
    invited_by          UUID REFERENCES users(id),
    invited_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    joined_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE(circle_id, user_id)
);

CREATE INDEX circle_members_user_idx   ON circle_members(user_id) WHERE deleted_at IS NULL;
CREATE INDEX circle_members_circle_idx ON circle_members(circle_id) WHERE deleted_at IS NULL;

ALTER TABLE circle_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_members FORCE ROW LEVEL SECURITY;

CREATE POLICY circle_members_read ON circle_members FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY circle_members_owner_manage ON circle_members FOR ALL TO app_user
  USING (circle_member_has_role(circle_id, ARRAY['owner']))
  WITH CHECK (circle_member_has_role(circle_id, ARRAY['owner']));

-- Enforce 8-member cap via trigger
CREATE OR REPLACE FUNCTION enforce_circle_member_cap() RETURNS TRIGGER AS $$
DECLARE
  member_count INT;
  cap INT;
BEGIN
  SELECT COUNT(*) INTO member_count FROM circle_members
   WHERE circle_id = NEW.circle_id AND deleted_at IS NULL;

  SELECT CASE subscription_tier
           WHEN 'free' THEN 3
           ELSE 8
         END INTO cap
    FROM circles WHERE id = NEW.circle_id;

  IF member_count >= cap THEN
    RAISE EXCEPTION 'Circle has reached its member cap of % for current plan', cap
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER circle_members_cap_trg
  BEFORE INSERT ON circle_members
  FOR EACH ROW EXECUTE FUNCTION enforce_circle_member_cap();

-- ---------- 4.10 Circle invitations ----------

CREATE TABLE circle_invitations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id       UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    invited_by      UUID NOT NULL REFERENCES users(id),
    role            member_role NOT NULL,
    code            TEXT NOT NULL UNIQUE,        -- 6-digit code shown to invitee
    invite_link_id  UUID NOT NULL DEFAULT uuid_generate_v4(),  -- in the share-sheet URL
    email           CITEXT,
    phone           TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    accepted_at     TIMESTAMPTZ,
    accepted_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX circle_invitations_circle_idx ON circle_invitations(circle_id);
CREATE INDEX circle_invitations_link_idx   ON circle_invitations(invite_link_id);

ALTER TABLE circle_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_invitations FORCE ROW LEVEL SECURITY;

CREATE POLICY invitations_member ON circle_invitations FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY invitations_owner_create ON circle_invitations FOR INSERT TO app_user
  WITH CHECK (circle_member_has_role(circle_id, ARRAY['owner']));

-- ---------- 4.11 Activities (the feed) ----------

CREATE TYPE activity_type AS ENUM (
  'voice_note',
  'text_note',
  'photo',
  'med_taken',
  'med_skipped',
  'med_missed',
  'vital_logged',
  'appointment_logged',
  'shift_started',
  'shift_ended',
  'document_added',
  'sos_triggered',
  'system'
);

CREATE TABLE activities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    author_user_id      UUID NOT NULL REFERENCES users(id),
    activity_type       activity_type NOT NULL,
    -- Plaintext display fields (intentionally minimal)
    headline            TEXT,                          -- "Sarah recorded a note"
    -- Encrypted PHI content
    content_enc         BYTEA,                         -- transcript or text body
    voice_object_key    TEXT,                          -- MinIO key for audio file
    photo_object_keys   TEXT[],                        -- MinIO keys for attached photos
    -- AI-extracted entities (encrypted JSON)
    entities_enc        BYTEA,
    -- Linkage
    related_med_id           UUID,
    related_appointment_id   UUID,
    related_shift_id         UUID,
    -- Metadata
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    -- Conflict resolution for concurrent edits
    version             BIGINT NOT NULL DEFAULT 1,
    client_op_id        UUID                           -- idempotency for offline sync
);

CREATE INDEX activities_circle_time_idx ON activities(circle_id, occurred_at DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX activities_author_idx ON activities(author_user_id);
CREATE INDEX activities_med_idx    ON activities(related_med_id) WHERE related_med_id IS NOT NULL;
CREATE UNIQUE INDEX activities_client_op_idx ON activities(circle_id, client_op_id)
  WHERE client_op_id IS NOT NULL;

ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities FORCE ROW LEVEL SECURITY;

CREATE POLICY activities_member_read ON activities FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY activities_member_write ON activities FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND author_user_id = current_user_id());

CREATE POLICY activities_author_update ON activities FOR UPDATE TO app_user
  USING (author_user_id = current_user_id() AND deleted_at IS NULL);

-- ---------- 4.12 Activity reactions ----------

CREATE TABLE activity_reactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id     UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,             -- denormalized for RLS
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji           TEXT NOT NULL,             -- 👍 ❤️ 🙏 etc.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(activity_id, user_id, emoji)
);

CREATE INDEX reactions_activity_idx ON activity_reactions(activity_id);
ALTER TABLE activity_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_reactions FORCE ROW LEVEL SECURITY;

CREATE POLICY reactions_member ON activity_reactions FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id) AND user_id = current_user_id());

-- ---------- 4.13 Activity comments ----------

CREATE TABLE activity_comments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id     UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    author_user_id  UUID NOT NULL REFERENCES users(id),
    content_enc     BYTEA NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX comments_activity_idx ON activity_comments(activity_id, created_at);
ALTER TABLE activity_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_comments FORCE ROW LEVEL SECURITY;

CREATE POLICY comments_member ON activity_comments FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id) AND author_user_id = current_user_id());

-- ---------- 4.14 Medications ----------

CREATE TYPE med_status AS ENUM ('active', 'as_needed', 'discontinued');

CREATE TABLE medications (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id             UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    -- Encrypted PHI
    name_enc              BYTEA NOT NULL,
    generic_name_enc      BYTEA,
    dosage_enc            BYTEA NOT NULL,     -- "10 mg"
    form                  TEXT,                -- 'tablet', 'capsule', 'liquid' — not PHI
    -- Non-PHI metadata
    rxcui                 TEXT,                -- RxNorm code (not PHI on its own)
    color                 TEXT,                -- UI color tag
    status                med_status NOT NULL DEFAULT 'active',
    -- Schedule
    schedule              JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Sources
    prescribing_provider_enc BYTEA,
    pharmacy_enc          BYTEA,
    notes_enc             BYTEA,
    start_date            DATE,
    end_date              DATE,
    -- Timestamps
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMPTZ
);

CREATE INDEX medications_circle_idx ON medications(circle_id) WHERE deleted_at IS NULL;
ALTER TABLE medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE medications FORCE ROW LEVEL SECURITY;

CREATE POLICY medications_member ON medications FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

-- Dose events (the actual record of each scheduled / taken dose)
CREATE TYPE dose_status AS ENUM ('scheduled', 'taken', 'skipped', 'missed', 'late');

CREATE TABLE dose_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    medication_id   UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    scheduled_at    TIMESTAMPTZ NOT NULL,
    taken_at        TIMESTAMPTZ,
    marked_by       UUID REFERENCES users(id),
    status          dose_status NOT NULL DEFAULT 'scheduled',
    notes_enc       BYTEA,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX dose_events_med_time_idx     ON dose_events(medication_id, scheduled_at);
CREATE INDEX dose_events_circle_time_idx  ON dose_events(circle_id, scheduled_at DESC);

ALTER TABLE dose_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE dose_events FORCE ROW LEVEL SECURITY;

CREATE POLICY dose_events_member ON dose_events FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.15 Appointments ----------

CREATE TABLE appointments (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                   UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    title_enc                   BYTEA NOT NULL,
    provider_enc                BYTEA,
    location_enc                BYTEA,
    starts_at                   TIMESTAMPTZ NOT NULL,
    duration_minutes            INT NOT NULL DEFAULT 60,
    transport_responsible       UUID REFERENCES users(id),
    prep_notes_enc              BYTEA,
    visit_summary_enc           BYTEA,
    reminder_minutes_before     INT[] DEFAULT '{1440, 60}'::INT[],
    created_by                  UUID NOT NULL REFERENCES users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at                  TIMESTAMPTZ
);

CREATE INDEX appointments_circle_time_idx ON appointments(circle_id, starts_at)
  WHERE deleted_at IS NULL;

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;
CREATE POLICY appointments_member ON appointments FOR ALL TO app_user
  USING (is_circle_member(circle_id)) WITH CHECK (is_circle_member(circle_id));

-- Appointment attendees (junction)
CREATE TABLE appointment_attendees (
    appointment_id  UUID REFERENCES appointments(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    PRIMARY KEY (appointment_id, user_id)
);

ALTER TABLE appointment_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_attendees FORCE ROW LEVEL SECURITY;
CREATE POLICY attendees_member ON appointment_attendees FOR ALL TO app_user
  USING (is_circle_member(circle_id)) WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.16 Care shifts ----------

CREATE TABLE care_shifts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    aide_user_id        UUID NOT NULL REFERENCES users(id),
    starts_at           TIMESTAMPTZ NOT NULL,
    ends_at             TIMESTAMPTZ NOT NULL,
    actual_start        TIMESTAMPTZ,
    actual_end          TIMESTAMPTZ,
    services            TEXT[] DEFAULT '{}'::TEXT[],   -- HCBS service codes
    notes_enc           BYTEA,
    miles_driven        NUMERIC(6,2),
    geofence_auto_detected BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX care_shifts_circle_time_idx ON care_shifts(circle_id, starts_at DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX care_shifts_aide_idx ON care_shifts(aide_user_id);

ALTER TABLE care_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_shifts FORCE ROW LEVEL SECURITY;
CREATE POLICY shifts_member ON care_shifts FOR ALL TO app_user
  USING (is_circle_member(circle_id)) WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.17 Documents ----------

CREATE TYPE document_type AS ENUM (
  'insurance_card', 'advance_directive', 'dnr', 'med_list',
  'visit_summary', 'eob', 'lab_result', 'identification', 'other'
);

CREATE TABLE documents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    title_enc           BYTEA NOT NULL,
    document_type       document_type NOT NULL,
    object_key          TEXT NOT NULL,                  -- MinIO key; file itself is E2EE
    mime_type           TEXT NOT NULL,
    size_bytes          BIGINT NOT NULL,
    encryption_nonce    BYTEA NOT NULL,                 -- per-file AES-GCM nonce
    encryption_tag      BYTEA NOT NULL,                 -- AES-GCM authentication tag
    issued_at           DATE,                           -- e.g., insurance card issued date
    expires_at          DATE,                           -- triggers a renewal reminder
    uploaded_by         UUID NOT NULL REFERENCES users(id),
    visibility          member_role[] NOT NULL DEFAULT '{owner,family_member,paid_family,care_recipient}'::member_role[],
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX documents_circle_idx ON documents(circle_id) WHERE deleted_at IS NULL;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE ROW LEVEL SECURITY;

-- Members can read documents only if their role is in the visibility list
CREATE POLICY documents_member_read ON documents FOR SELECT TO app_user
  USING (
    is_circle_member(circle_id) AND
    EXISTS (
      SELECT 1 FROM circle_members cm
      WHERE cm.circle_id = documents.circle_id
        AND cm.user_id   = current_user_id()
        AND cm.role      = ANY(documents.visibility)
        AND cm.deleted_at IS NULL
    )
  );

CREATE POLICY documents_member_write ON documents FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND uploaded_by = current_user_id());

-- ---------- 4.18 Emergency contacts ----------

CREATE TABLE emergency_contacts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    name_enc            BYTEA NOT NULL,
    relationship        TEXT,                       -- 'son', 'doctor', '911' — not PHI on its own
    phone_enc           BYTEA NOT NULL,
    is_primary          BOOLEAN NOT NULL DEFAULT FALSE,
    is_medical          BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order          INT NOT NULL DEFAULT 100,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX emergency_contacts_circle_idx ON emergency_contacts(circle_id, sort_order)
  WHERE deleted_at IS NULL;

ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY ec_member ON emergency_contacts FOR ALL TO app_user
  USING (is_circle_member(circle_id)) WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.19 SOS events ----------

CREATE TABLE sos_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    triggered_by        UUID NOT NULL REFERENCES users(id),
    triggered_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    canceled_at         TIMESTAMPTZ,
    canceled_by         UUID REFERENCES users(id),
    location_lat        NUMERIC(9,6),
    location_lng        NUMERIC(9,6),
    location_accuracy_m NUMERIC(6,1),
    notified_user_ids   UUID[] NOT NULL DEFAULT '{}'::UUID[],
    primary_contact_called BOOLEAN NOT NULL DEFAULT FALSE,
    resolution_notes_enc BYTEA
);

CREATE INDEX sos_circle_time_idx ON sos_events(circle_id, triggered_at DESC);
ALTER TABLE sos_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_events FORCE ROW LEVEL SECURITY;
CREATE POLICY sos_member ON sos_events FOR ALL TO app_user
  USING (is_circle_member(circle_id)) WITH CHECK (is_circle_member(circle_id));

-- ---------- 4.20 Care minutes (paid caregiver Pro tier) ----------

CREATE TABLE care_minute_entries (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    caregiver_user_id   UUID NOT NULL REFERENCES users(id),
    shift_id            UUID REFERENCES care_shifts(id),
    service_code        TEXT NOT NULL,           -- HCBS code, e.g., 'T1019', 'S5125'
    service_description TEXT NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ NOT NULL,
    duration_minutes    INT NOT NULL,
    notes_enc           BYTEA,
    fiscal_intermediary TEXT,                    -- 'PPL', 'Acumen', 'Easterseals'
    exported_at         TIMESTAMPTZ,
    export_pdf_key      TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX care_min_circle_time_idx ON care_minute_entries(circle_id, started_at DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX care_min_caregiver_idx ON care_minute_entries(caregiver_user_id, started_at DESC);

ALTER TABLE care_minute_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_minute_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY cm_caregiver ON care_minute_entries FOR ALL TO app_user
  USING (is_circle_member(circle_id) AND
         (caregiver_user_id = current_user_id() OR
          circle_member_has_role(circle_id, ARRAY['owner'])))
  WITH CHECK (caregiver_user_id = current_user_id());

-- ---------- 4.21 Pending operations (server-side idempotency) ----------

CREATE TABLE pending_operations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_op_id    UUID NOT NULL,
    user_id         UUID NOT NULL REFERENCES users(id),
    circle_id       UUID,
    operation_type  TEXT NOT NULL,
    payload         JSONB NOT NULL,
    processed_at    TIMESTAMPTZ,
    result          JSONB,
    error           TEXT,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, client_op_id)
);

CREATE INDEX pending_ops_user_idx ON pending_operations(user_id, received_at DESC);

-- ---------- 4.22 Audit trigger function ----------

CREATE OR REPLACE FUNCTION audit_trigger_fn() RETURNS TRIGGER AS $$
DECLARE
  v_old JSONB;
  v_new JSONB;
  v_row_id UUID;
  v_circle_id UUID;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_old := to_jsonb(OLD);
    v_row_id := OLD.id;
    v_circle_id := COALESCE(OLD.circle_id, NULL);
  ELSIF (TG_OP = 'UPDATE') THEN
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_row_id := NEW.id;
    v_circle_id := COALESCE(NEW.circle_id, NULL);
  ELSE
    v_new := to_jsonb(NEW);
    v_row_id := NEW.id;
    v_circle_id := COALESCE(NEW.circle_id, NULL);
  END IF;

  INSERT INTO audit_log (
    actor_id, circle_id, action, table_name, row_id, diff
  ) VALUES (
    current_user_id(),
    v_circle_id,
    TG_OP,
    TG_TABLE_NAME,
    v_row_id,
    jsonb_build_object('before', v_old, 'after', v_new)
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach audit to every PHI table
CREATE TRIGGER audit_care_recipients   AFTER INSERT OR UPDATE OR DELETE ON care_recipients   FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_activities        AFTER INSERT OR UPDATE OR DELETE ON activities        FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_medications       AFTER INSERT OR UPDATE OR DELETE ON medications       FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_dose_events       AFTER INSERT OR UPDATE OR DELETE ON dose_events       FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_appointments      AFTER INSERT OR UPDATE OR DELETE ON appointments      FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_care_shifts       AFTER INSERT OR UPDATE OR DELETE ON care_shifts       FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_documents         AFTER INSERT OR UPDATE OR DELETE ON documents         FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_circle_members    AFTER INSERT OR UPDATE OR DELETE ON circle_members    FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_sos_events        AFTER INSERT OR UPDATE OR DELETE ON sos_events        FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
CREATE TRIGGER audit_care_minute       AFTER INSERT OR UPDATE OR DELETE ON care_minute_entries FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- ---------- 4.23 updated_at trigger ----------

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated     BEFORE UPDATE ON users     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_circles_updated   BEFORE UPDATE ON circles   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
-- (repeat for every table with updated_at)
```

---

## 5. Backend API service (Node.js + Fastify)

### 5.1 Tech choice

- **Node.js 22 LTS + Fastify 5** — Fast, low-memory, mature, excellent ergonomics. Justin already uses Node.
- **TypeScript** — Required. No JavaScript in v1.
- **Drizzle ORM** — Type-safe query builder, lightweight, generates migrations from schema. Better than Prisma for this use case because it leaves you closer to raw SQL where RLS lives.
- **pg-listen** — For Postgres LISTEN/NOTIFY → WebSocket fanout.
- **jose** — For JWT signing and Apple JWT verification.
- **BullMQ** — Job queue on Redis for APNs fan-out, OpenAI proxy calls, openFDA lookups, PDF generation.

### 5.2 Authentication flow (Sign in with Apple)

1. iOS app calls `ASAuthorizationAppleIDProvider`, receives an `identityToken` (JWT signed by Apple).
2. iOS posts `{ identityToken, nonce }` to `POST /v1/auth/apple`.
3. Server:
   - Fetches Apple's public keys from `https://appleid.apple.com/auth/keys` (cached for 1 hour).
   - Verifies the JWT signature and validates `iss`, `aud`, `exp`, `nonce`.
   - Extracts `sub` (the stable Apple user ID).
   - Upserts a row in `users` keyed on `apple_user_id = sub`.
   - Mints two CareCircle JWTs:
     - **Access token** (15-minute lifetime, contains `user_id`, `iat`, `exp`)
     - **Refresh token** (30-day lifetime, opaque random token; persisted in Redis with the user_id)
   - Returns both to iOS.
4. iOS stores both tokens in the Keychain.
5. Subsequent requests carry `Authorization: Bearer <access_token>`.
6. When access token expires, iOS POSTs the refresh token to `/v1/auth/refresh` to get a new pair.

The server JWT is signed with **HS256 and a 256-bit secret in Railway env vars**. Rotate the secret quarterly using a versioned key id (`kid` header).

### 5.3 RLS context setting (the critical pattern)

This is the single most important piece of the backend. **Every authenticated request sets a session variable that RLS policies read.**

```typescript
// fastify request hook (preHandler)
async function setRlsContext(req: FastifyRequest, _reply: FastifyReply) {
  const userId = req.user.id;
  await req.pgClient.query(`SET LOCAL app.current_user_id = $1`, [userId]);
  // Optional circle scoping for circle-bound routes:
  if (req.params?.circleId) {
    await req.pgClient.query(`SET LOCAL app.current_circle_id = $1`, [req.params.circleId]);
  }
}
```

**Crucial detail:** Use `SET LOCAL`, not `SET`. `SET LOCAL` is scoped to the transaction, so the value disappears when the request ends. With PgBouncer in transaction mode, this is the only safe way to scope context. Without `LOCAL`, the variable could leak to another user on the same pooled connection.

Use a single connection-per-request pattern via Drizzle's transaction wrapper:
```typescript
await db.transaction(async (tx) => {
  await tx.execute(sql`SET LOCAL app.current_user_id = ${userId}`);
  // … all queries in this request use tx
});
```

### 5.4 Conflict resolution policy

Offline-first means conflicts. Policy by entity:

| Entity | Strategy | Rationale |
|---|---|---|
| `activities` | Last-write-wins on body; reactions and comments append-only (no conflict possible) | Activities are typically authored by one person |
| `dose_events` | Last-write-wins; `taken_at` is monotonic on conflict (later wins) | Marking taken is idempotent in effect |
| `medications.schedule` | Last-write-wins by `updated_at` with a server-side merge of new entries | Schedules rarely conflict |
| `documents` | No conflicts — documents are write-once-then-replace | New version creates a new row |
| `care_shifts` | Last-write-wins; surface conflicts to user when actual_start/actual_end conflict | Time conflicts need human review |
| `care_minute_entries` | Reject conflicting writes (HTTP 409) | Billing data must not silently merge |

Server attaches a monotonic `version` column to every PHI row. On UPDATE, client must send the version they last saw; server returns 409 Conflict if it has advanced.

### 5.5 API endpoint inventory (v1)

```
Auth
  POST   /v1/auth/apple                Verify SiwA token, return access+refresh
  POST   /v1/auth/refresh              Exchange refresh for new pair
  POST   /v1/auth/logout               Revoke refresh token

Users
  GET    /v1/me                        Current user profile
  PATCH  /v1/me                        Update display_name, photo
  DELETE /v1/me                        Delete account (soft delete, 30-day grace)
  POST   /v1/me/devices                Register APNs token
  DELETE /v1/me/devices/:id            Unregister

Circles
  POST   /v1/circles                   Create circle
  GET    /v1/circles                   List my circles
  GET    /v1/circles/:id               Get circle
  PATCH  /v1/circles/:id               Update circle settings
  DELETE /v1/circles/:id               Delete circle (soft, owner only)

Care Recipients
  PUT    /v1/circles/:id/recipient     Set/update care recipient
  GET    /v1/circles/:id/recipient

Members
  GET    /v1/circles/:id/members
  POST   /v1/circles/:id/members/:userId   Update role (owner only)
  DELETE /v1/circles/:id/members/:userId   Remove member

Invitations
  POST   /v1/circles/:id/invitations   Create invitation
  POST   /v1/invitations/:code/accept  Accept by code
  POST   /v1/invitations/link/:linkId/accept  Accept by link

Activities
  POST   /v1/circles/:id/activities    Create activity
  GET    /v1/circles/:id/activities    List with cursor pagination
  GET    /v1/activities/:id            Single activity
  PATCH  /v1/activities/:id            Edit (author only)
  DELETE /v1/activities/:id            Soft delete

Reactions & Comments
  POST   /v1/activities/:id/reactions
  DELETE /v1/activities/:id/reactions/:emoji
  POST   /v1/activities/:id/comments
  GET    /v1/activities/:id/comments

Medications
  POST   /v1/circles/:id/medications
  GET    /v1/circles/:id/medications
  PATCH  /v1/medications/:id
  DELETE /v1/medications/:id
  POST   /v1/medications/:id/doses/mark-taken
  POST   /v1/medications/:id/scan      Process scanned label (calls OCR + RxNorm)

Appointments
  POST   /v1/circles/:id/appointments
  GET    /v1/circles/:id/appointments
  PATCH  /v1/appointments/:id
  DELETE /v1/appointments/:id

Shifts (paid aide use)
  POST   /v1/circles/:id/shifts
  GET    /v1/circles/:id/shifts
  POST   /v1/shifts/:id/clock-in
  POST   /v1/shifts/:id/clock-out

Documents
  POST   /v1/circles/:id/documents/upload-url   Returns signed MinIO PUT URL
  POST   /v1/circles/:id/documents             Confirms upload, creates row
  GET    /v1/circles/:id/documents
  GET    /v1/documents/:id/download-url        Returns signed GET URL
  DELETE /v1/documents/:id

Emergency Contacts
  GET    /v1/circles/:id/emergency-contacts
  POST   /v1/circles/:id/emergency-contacts
  PATCH  /v1/emergency-contacts/:id
  DELETE /v1/emergency-contacts/:id

SOS
  POST   /v1/circles/:id/sos           Trigger SOS (worker fans out push + calls)
  POST   /v1/sos/:id/cancel
  POST   /v1/sos/:id/resolve

Care Minutes
  POST   /v1/circles/:id/care-minutes
  GET    /v1/circles/:id/care-minutes
  POST   /v1/circles/:id/care-minutes/export-pdf  Queues worker job

Realtime
  WS     /v1/realtime?token=<access_token>

Sync
  POST   /v1/sync/batch                Replay multiple offline operations atomically
```

### 5.6 Realtime (WebSocket fan-out)

Postgres `LISTEN/NOTIFY` is the source of truth. After any INSERT/UPDATE/DELETE on a PHI table, a trigger emits:

```sql
NOTIFY circle_changes, '{"circle_id":"...","table":"activities","row_id":"...","op":"INSERT"}';
```

The API service has one `pg-listen` subscriber per process. When a NOTIFY arrives, it broadcasts to all WebSocket clients connected to that circle (tracked in an in-memory Map). The WebSocket message contains only the row ID and table — clients fetch the actual row through the normal RLS-protected API. This keeps the realtime channel narrow and prevents accidental over-sharing.

For horizontal scaling (multiple API replicas), use Redis pub/sub to relay NOTIFY across instances.

---

## 6. Object storage (MinIO on Railway)

### 6.1 Buckets

| Bucket | Contents | Access |
|---|---|---|
| `cc-photos` | Photos attached to activities and Care Recipient profile | Signed URLs only, 1-hour expiry |
| `cc-voice` | Audio files for voice handoff notes | Signed URLs only, 1-hour expiry |
| `cc-documents` | Insurance cards, advance directives, etc. (E2EE) | Signed URLs only, 5-minute expiry |
| `cc-pdf-exports` | Generated care-minutes PDFs | Signed URLs only, 24-hour expiry |
| `cc-backups` | Encrypted nightly DB dumps | Service-role only |

All buckets configured with:
- Server-side encryption at rest (SSE-S3, MinIO native)
- Versioning enabled (recover from accidental delete)
- Lifecycle rule: documents marked deleted are purged after 90 days

### 6.2 Upload flow

1. iOS requests `POST /v1/circles/:id/documents/upload-url` with file size and content type.
2. Server validates (size cap 25 MB, MIME whitelist), generates a pre-signed PUT URL for MinIO valid for 5 minutes.
3. iOS encrypts the file in memory using CryptoKit AES-GCM with the circle key, then PUTs the ciphertext directly to MinIO.
4. iOS POSTs the resulting object key and encryption metadata (nonce, tag) back to the server.
5. Server creates the `documents` row.

This means MinIO never sees plaintext document content. Only circle members with the circle key (held in their Keychain, propagated via the invitation flow) can decrypt.

### 6.3 What's NOT end-to-end encrypted

Activity content, medication names, appointment notes, etc. — these use server-side pgcrypto encryption. The server can read them (necessary for AI entity extraction and search). The tradeoff: trusting Railway with these fields, in exchange for server-side intelligence.

Documents are special because:
- They contain the highest-risk PHI (SSN on insurance cards, full medical history in directives)
- They don't need server-side processing
- They're the easiest category to E2EE

---

## 7. Security posture

### 7.1 Defense layers

1. **Transport:** TLS 1.3 everywhere, certificate pinning in iOS for `api.carecircle.app`.
2. **Authentication:** Sign in with Apple only. No passwords. Refresh tokens rotated on every use.
3. **Authorization:** RLS on every PHI table. Server cannot accidentally over-fetch.
4. **Encryption at rest:** Railway encrypted volumes + pgcrypto column encryption + CryptoKit E2EE for documents.
5. **Audit:** Every PHI write logged to `audit_log` immutably. Owners can view audit for their circle via the API.
6. **Rate limiting:** Redis-backed per-user limits — 100 req/min for normal endpoints, 10 req/min for auth.
7. **Input validation:** Zod schemas on every endpoint. Reject anything unexpected.
8. **Secrets:** All keys in Railway env vars, scoped per-service. No secrets in the repo. Use Railway's reference variables to share between services.
9. **Dependencies:** `npm audit` in CI, fail on high or critical.
10. **Logging:** No PHI in logs. Ever. Use a redacting logger.

### 7.2 HIPAA path

CareCircle in v1 is a **personal-use family tool**, not a HIPAA-covered entity. Position the ToS and privacy policy accordingly. When you're ready to go B2B (home-care agency partnerships, v3):

1. Sign Railway's BAA via trust.railway.com (available as add-on).
2. Confirm BAAs for any sub-processors (Apple APNs is covered by Apple's standard BAA).
3. Complete a Security Risk Analysis per 45 CFR §164.308(a)(1)(ii)(A).
4. Establish breach notification procedures.
5. Train any human staff with database access.
6. Document everything.

The schema is already HIPAA-aligned (audit log, RLS, encryption, access controls). The remaining work is administrative, not architectural.

### 7.3 Specific threats and mitigations

| Threat | Mitigation |
|---|---|
| Stolen iOS device | Sign in with Apple requires Face ID / Apple ID auth; refresh token is in Keychain (encrypted with Secure Enclave) |
| Compromised access token | 15-minute lifetime; revoke refresh token on suspicious activity |
| Compromised refresh token | Rotation on every use; old token invalidated; mismatched chain triggers global logout |
| SQL injection | Parameterized queries via Drizzle; no string concatenation |
| Cross-circle data leak | RLS enforced at DB; double-checked in API; integration tests assert it |
| Brute force on invite codes | Codes are 6 alphanumeric chars (~2B space); 5 failed attempts per IP/hour locks the code |
| Insider threat (Railway employee) | Column encryption + E2EE on documents; with BAA, Railway employees can't access workloads |
| Disk seizure | Railway volumes are encrypted; pgcrypto adds a second layer |
| Backup theft | Backups encrypted with separate key before upload to MinIO |
| DoS | Railway's edge + Cloudflare in front for the API service |

---

## 8. SwiftData local cache schema (iOS side)

The iOS SwiftData schema mirrors the Postgres schema with a few additions for sync state. Showing the additions only here; the rest matches the original product spec.

```swift
@Model final class PendingOperation {
    @Attribute(.unique) var id: UUID
    var clientOpId: UUID
    var operationType: String   // "create_activity", "mark_dose_taken", etc.
    var payload: Data           // JSON encoded
    var targetCircleId: UUID?
    var createdAt: Date
    var lastAttemptedAt: Date?
    var attemptCount: Int
    var status: String          // "pending", "in_flight", "succeeded", "failed"
    var errorMessage: String?

    init(operationType: String, payload: Data, targetCircleId: UUID? = nil) {
        self.id = UUID()
        self.clientOpId = UUID()
        self.operationType = operationType
        self.payload = payload
        self.targetCircleId = targetCircleId
        self.createdAt = Date()
        self.attemptCount = 0
        self.status = "pending"
    }
}

@Model final class SyncCursor {
    @Attribute(.unique) var entityName: String   // "activities", "medications", etc.
    var lastSyncedAt: Date
    var lastSeenServerVersion: Int64

    init(entityName: String) {
        self.entityName = entityName
        self.lastSyncedAt = .distantPast
        self.lastSeenServerVersion = 0
    }
}

@Model final class CircleKey {
    @Attribute(.unique) var circleId: UUID
    var symmetricKeyData: Data   // stored in Keychain, NOT SwiftData (this is a stub)
    var keyVersion: Int
    var addedAt: Date
}
```

**Important:** `CircleKey.symmetricKeyData` is shown for reference but is actually stored in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Never put symmetric keys in SwiftData.

The `SyncEngine` actor polls `pending_operations` and replays them on a Reachability-driven schedule.

---

## 9. Migrations and DDL management

### 9.1 Tool

Use **Drizzle Kit** for migrations. Each migration is a numbered SQL file, checked into git.

```
backend/
  src/
  drizzle/
    schema.ts                  # Drizzle schema (source of truth for ORM)
    migrations/
      0001_initial.sql
      0002_add_care_minutes.sql
      0003_add_audit_triggers.sql
  drizzle.config.ts
```

### 9.2 Migration workflow

1. Modify `schema.ts`.
2. Run `pnpm drizzle-kit generate` to emit a new SQL migration.
3. Manually review the generated SQL. Hand-edit for RLS policies, triggers, anything Drizzle doesn't model.
4. Run `pnpm drizzle-kit migrate` against staging.
5. Run integration tests against staging.
6. Merge to main. Railway auto-deploys; production migration runs on deploy via a `prestart` hook.

### 9.3 What Drizzle does NOT manage (do these by hand in SQL files)

- RLS policies
- Triggers
- Functions
- Extensions
- Roles and grants

Keep a separate `drizzle/manual/` folder for these. Apply manual migrations before Drizzle-generated ones in CI.

---

## 10. Testing the database

### 10.1 RLS test suite (mandatory)

Every PHI table must have an RLS test asserting cross-circle isolation. Pattern (using Vitest):

```typescript
describe('activities RLS', () => {
  it('user in circle A cannot read activities in circle B', async () => {
    const { userA, circleA } = await seedCircleWithUser();
    const { circleB }        = await seedCircleWithUser();
    await insertActivity(circleB.id);   // via service role

    const rowsAsA = await asUser(userA.id).select().from(activities).where(eq(activities.circleId, circleB.id));
    expect(rowsAsA).toEqual([]);
  });
});
```

Run these on every PR. They are the single most important test category.

### 10.2 Migration safety tests

A separate CI job that:
1. Spins up a Postgres container.
2. Runs every migration from 0001 onward.
3. Asserts the resulting schema matches the expected snapshot.
4. Loads a small fixture dataset.
5. Reverts each migration in reverse if `down` is provided.

### 10.3 Load tests

Use `k6` against a staging deployment. Targets for v1:
- 100 concurrent WebSocket clients per circle: <100 ms p95 latency on activity broadcast
- 1000 req/s on `GET /v1/circles/:id/activities`: <80 ms p95
- 50 concurrent voice-note uploads (10 MB each): no failures

---

## 11. Deployment runbook (Railway)

### 11.1 Project layout

One Railway project, named `carecircle-prod`. Services:

| Service | Source | Public | Resources |
|---|---|---|---|
| `postgres` | Railway Postgres plugin | No | 1GB RAM |
| `pgbouncer` | Custom Dockerfile | No | 256MB |
| `redis` | Railway Redis plugin | No | 256MB |
| `minio` | Bitnami MinIO image | No | 512MB + 50GB volume |
| `api` | This monorepo, `apps/api` | Yes (`api.carecircle.app`) | 512MB, 2 replicas |
| `worker` | This monorepo, `apps/worker` | No | 512MB |
| `migrator` | This monorepo, `apps/migrator` | No, run-on-deploy only | 256MB |

A separate `carecircle-staging` project mirrors prod with smaller resources.

### 11.2 Environment variables (per service)

Use Railway's **reference variables** to share secrets cleanly:

```
# api service
DATABASE_URL              = ${{ pgbouncer.DATABASE_URL }}
DIRECT_DATABASE_URL       = ${{ postgres.DATABASE_URL }}
REDIS_URL                 = ${{ redis.REDIS_URL }}
MINIO_ENDPOINT            = ${{ minio.PRIVATE_URL }}
MINIO_ACCESS_KEY          = (secret)
MINIO_SECRET_KEY          = (secret)
JWT_SECRET                = (secret, 256-bit)
JWT_KID                   = v1
APPLE_TEAM_ID             = (Apple Developer)
APPLE_KEY_ID              = (Apple Developer)
APPLE_CLIENT_ID           = app.carecircle.ios
APPLE_PRIVATE_KEY         = (the .p8 contents, base64)
APNS_KEY_ID               = (Apple Developer)
APNS_TEAM_ID              = (same as APPLE_TEAM_ID)
APNS_PRIVATE_KEY          = (the APNs .p8, base64)
APNS_BUNDLE_ID            = app.carecircle.ios
OPENAI_API_KEY            = (for fallback LLM only)
OPENFDA_API_KEY           = (optional; unauthenticated works)
SENTRY_DSN                = (error tracking)
NODE_ENV                  = production
LOG_LEVEL                 = info
```

### 11.3 Initial bootstrap

1. Create the Railway project.
2. Add Postgres plugin. Run the schema SQL from §4 via `psql`.
3. Add Redis plugin.
4. Deploy MinIO from a `Dockerfile`.
5. Deploy `pgbouncer`.
6. Deploy `api` and `worker` from the monorepo.
7. Create a `migrator` service that runs `drizzle-kit migrate && exit` on each deploy.
8. Point `api.carecircle.app` at the `api` service (Railway custom domain).
9. Smoke-test with a `curl` against `/v1/health`.

### 11.4 CI/CD

GitHub Actions workflow:
1. PR: lint, type-check, unit tests, RLS tests on a Postgres container.
2. Main: above + deploy `staging` Railway project.
3. Tag `v*.*.*`: deploy `prod`. Manual approval gate.

---

## 12. Open questions

These don't block v1 but should be revisited.

1. **MinIO vs Cloudflare R2** — R2 has lower egress costs at scale. Plan to migrate at >5,000 circles.
2. **Postgres replicas** — Add a read replica when query load gets unbalanced. Not needed in v1.
3. **Search** — No full-text search in v1 (encrypted content prevents it). When needed, consider a separate ElasticSearch service with deliberate redaction of indexed content.
4. **Multi-region** — Single US-East region in v1. Multi-region adds significant complexity and isn't justified until international users.
5. **End-to-end encryption for activity content** — A future option, but requires server-side AI changes (extraction would have to happen on-device).

---

## 13. Quick reference: data flow for the "voice handoff" feature

This is the most complex flow in the app. End-to-end:

1. **User taps mic on iOS.** SwiftUI view starts AVAudioRecorder.
2. **User stops recording.** SFSpeechRecognizer transcribes on-device.
3. **iOS encrypts audio file** with circle key, requests upload URL.
4. `POST /v1/circles/:id/documents/upload-url` returns MinIO pre-signed PUT. RLS verifies user is in circle.
5. **iOS PUTs encrypted audio** to MinIO. MinIO writes to disk.
6. **iOS POSTs activity** with transcript + voice object key + entities.
7. `POST /v1/circles/:id/activities`:
   - Validates payload (Zod)
   - Opens transaction; sets RLS context
   - INSERTs into `activities` (encrypts content with pgcrypto)
   - Audit trigger fires, writes to `audit_log`
   - NOTIFY fires on `circle_changes` channel
   - Returns activity row
8. **API process** receives NOTIFY via pg-listen, fans out via WebSocket.
9. **Other circle members' iOS apps** receive WS message with `{circleId, table, rowId}`.
10. **Each app** does `GET /v1/activities/:id`, RLS allows, decrypts client-side, writes to SwiftData, UI updates.
11. **Worker** picks up a "new_activity" job from BullMQ, sends APNs push to offline members based on their notification preferences.

Total time, hot path, US users: ~600 ms tap-to-broadcast.

---

*End of CareCircle database and backend specification, v1.0.*
