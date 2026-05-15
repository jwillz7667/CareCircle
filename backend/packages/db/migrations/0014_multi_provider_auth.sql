-- =====================================================================
-- 0014 Multi-provider auth: Google sub + email/password hash
--
-- Adds two optional auth columns to `users` so the same row can identify
-- across Apple, Google, and email + password sign-in. A user needs at
-- least one method — enforced by a CHECK constraint.
--
-- `apple_user_id` is relaxed from NOT NULL: Google-only and email-only
-- users would otherwise need a synthetic Apple sub, which conflates
-- identity models. The existing UNIQUE index still rejects duplicate
-- Apple subs but tolerates NULL (Postgres treats multiple NULLs as
-- distinct under UNIQUE).
--
-- `password_hash` stores an Argon2id PHC string (e.g.
-- `$argon2id$v=19$m=...,t=...,p=...$<salt>$<hash>`). The verifier reads
-- parameters from the string itself, so no separate `password_algo`
-- column is needed.
--
-- `password_updated_at` is recorded on register and on password change
-- so a future "revoke sessions issued before password change" sweep can
-- find affected refresh tokens. Not enforced at v1; column reserved.
-- =====================================================================

ALTER TABLE users
    ALTER COLUMN apple_user_id DROP NOT NULL,
    ADD COLUMN google_user_id      TEXT UNIQUE,
    ADD COLUMN password_hash       TEXT,
    ADD COLUMN password_updated_at TIMESTAMPTZ;

ALTER TABLE users
    ADD CONSTRAINT users_has_auth_method CHECK (
        apple_user_id  IS NOT NULL
        OR google_user_id IS NOT NULL
        OR password_hash  IS NOT NULL
    );
