-- ============================================================================
-- 034_driver_substitutes.sql — Phase 7: driver substitute relationships
--
-- A lightweight server-side record associating a primary driver, an
-- independent substitute account, one vehicle of the primary's profile, an
-- explicit permission set, mutual confirmations, and validity windows.
--
-- Identity rules encoded by the schema:
--   * substitute_user_id references users(id) directly — the substitute acts
--     under their OWN account; there is no column through which primary
--     credentials, refresh tokens, or biometric state could be inherited.
--   * Wallets, earnings, and profiles are never referenced here; a
--     relationship grants operational permissions only, and the server
--     authorizes the actual acting driver on every operation.
--   * Invitations carry a single-use random token stored only as a SHA-256
--     digest (never the raw token) with its own expiry, so a leaked row can
--     never be replayed to accept an invite.
--
-- Status machine (see nidus/domain/entities/substitute.go):
--   invited -> pending_substitute_confirmation -> pending_primary_confirmation
--           -> active -> revoked | expired | suspended
-- 'expired' is derived at read time once valid_until passes; 'revoked'/'
-- suspended' are terminal-for-authorization states written by revoke/suspend.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS driver_substitute_relationships (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    primary_driver_id           UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    substitute_user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_label               TEXT NULL CHECK (vehicle_label IS NULL OR char_length(vehicle_label) <= 80),
    permissions                 TEXT[] NOT NULL DEFAULT ARRAY['accept_rides']::TEXT[],
    status                      VARCHAR(40) NOT NULL DEFAULT 'invited' CHECK (status IN
                                ('invited','pending_substitute_confirmation',
                                 'pending_primary_confirmation','active',
                                 'expired','suspended','revoked')),
    invite_token_hash           CHAR(64) NULL,
    invite_expires_at           TIMESTAMPTZ NULL,
    accepted_by_substitute_at   TIMESTAMPTZ NULL,
    confirmed_by_primary_at     TIMESTAMPTZ NULL,
    activated_at                TIMESTAMPTZ NULL,
    valid_from                  TIMESTAMPTZ NULL,
    valid_until                 TIMESTAMPTZ NULL,
    revoked_at                  TIMESTAMPTZ NULL,
    revoke_reason               TEXT NULL CHECK (revoke_reason IS NULL OR char_length(revoke_reason) <= 120),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Validity window, when both bounds are set, must be ordered.
    CHECK (valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from),
    -- An invitation token belongs to an invite stage only; once the flow has
    -- moved past 'invited' the digest is consumed and cleared.
    CHECK (status <> 'invited' OR invite_token_hash IS NOT NULL),
    CHECK (status = 'invited' OR invite_token_hash IS NULL)
);

-- One live relationship per (primary, substitute, vehicle). Vehicle label is
-- normalized to '' for "no specific vehicle" so NULL and empty cannot create
-- two parallel rows for the same pair.
ALTER TABLE driver_substitute_relationships
    ADD COLUMN IF NOT EXISTS vehicle_key TEXT GENERATED ALWAYS AS (COALESCE(vehicle_label, '')) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS uq_substitute_live_relationship
    ON driver_substitute_relationships(primary_driver_id, substitute_user_id, vehicle_key)
    WHERE status IN ('invited','pending_substitute_confirmation','pending_primary_confirmation','active');

-- Substitute-side lookups (the substitute lists/acts on their invitations)
-- and primary-side dashboards must both be index hits; partial predicates
-- keep the hot "who may act right now" query cheap.
CREATE INDEX IF NOT EXISTS idx_substitute_by_primary
    ON driver_substitute_relationships(primary_driver_id) WHERE status IN ('invited','pending_substitute_confirmation','pending_primary_confirmation','active','suspended');
CREATE INDEX IF NOT EXISTS idx_substitute_by_user
    ON driver_substitute_relationships(substitute_user_id) WHERE status IN ('invited','pending_substitute_confirmation','pending_primary_confirmation','active','suspended');
CREATE INDEX IF NOT EXISTS idx_substitute_active_lookup
    ON driver_substitute_relationships(substitute_user_id, valid_until) WHERE status = 'active';

COMMENT ON TABLE driver_substitute_relationships IS 'Phase 7: primary-driver <-> independent-substitute authorization records. Grants explicit operational permissions on one vehicle; never transfers wallet, earnings, profile, or login credentials.';

COMMIT;
