-- ============================================================================
-- 032_rider_activation (down)
-- Reverts the rider activation columns added by 032_rider_activation.sql.
-- ============================================================================

BEGIN;

DROP INDEX IF EXISTS idx_users_not_activated;

ALTER TABLE legal_documents DROP COLUMN IF EXISTS requires_activation;
ALTER TABLE users DROP COLUMN IF EXISTS activated_at;
ALTER TABLE users DROP COLUMN IF EXISTS onboarding_complete;

COMMIT;
