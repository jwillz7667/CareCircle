-- =====================================================================
-- 0009 Refresh tokens (server-managed JWT refresh chain)
-- =====================================================================

CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL UNIQUE,
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    last_used_at    TIMESTAMPTZ,
    rotated_from    UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL,
    revoked_at      TIMESTAMPTZ,
    user_agent      TEXT,
    ip_address      INET
);

CREATE INDEX refresh_tokens_user_idx ON refresh_tokens(user_id, revoked_at);
CREATE INDEX refresh_tokens_hash_idx ON refresh_tokens(token_hash);

-- Only the service role manages tokens; app_user never sees them.
GRANT SELECT, INSERT, UPDATE ON refresh_tokens TO app_service;
REVOKE ALL ON refresh_tokens FROM app_user, app_anon;
ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens FORCE ROW LEVEL SECURITY;
