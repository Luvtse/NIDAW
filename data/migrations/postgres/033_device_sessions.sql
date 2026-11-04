-- ============================================================================
-- 033_device_sessions.sql — Phase 5: persistent device sessions
--
-- One row per authenticated device session. The refresh credential is stored
-- only as a SHA-256 hash (never the token itself). Rotation creates a child
-- row linked via rotated_from within the same family_id; reuse of a consumed
-- or revoked row revokes the whole family. Idle expiry is enforced through
-- last_used_at + the server-side idle policy; absolute expiry lives in
-- expires_at. All permanent session records stay in PostgreSQL; Redis keeps
-- only ephemeral JTI denylist/rotation state.
-- ============================================================================

CREATE TABLE IF NOT EXISTS auth_device_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id           UUID NOT NULL,
    refresh_token_hash  CHAR(64) NOT NULL,
    rotated_from        UUID NULL REFERENCES auth_device_sessions(id) ON DELETE SET NULL,
    device_name         TEXT NULL CHECK (device_name IS NULL OR char_length(device_name) <= 120),
    platform            TEXT NULL CHECK (platform IS NULL OR char_length(platform) <= 40),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ NULL,
    revoke_reason       TEXT NULL CHECK (revoke_reason IS NULL OR char_length(revoke_reason) <= 60)
);

CREATE INDEX IF NOT EXISTS idx_device_sessions_user
    ON auth_device_sessions(user_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_device_sessions_family
    ON auth_device_sessions(family_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_sessions_active_hash
    ON auth_device_sessions(refresh_token_hash) WHERE revoked_at IS NULL;

-- Sessions must not outlive their user's absolute-refresh window by accident;
-- callers are required to pass expires_at = issued_at + REFRESH_TOKEN_TTL.
