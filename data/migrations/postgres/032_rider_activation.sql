-- ============================================================================
-- 032_rider_activation
-- Rider registration & activation support (Auth roadmap Phase 3).
--
-- Rationale: riders authenticate with phone + OTP and are activated once they
-- accept the required legal agreements. Activation state must be durable so
-- both apps can gate onboarding ("skip and complete later") without inferring
-- it from optional profile fields. Legal consents themselves keep living in
-- the existing user_consents / consent_audit_log tables (001 schema) — this
-- migration only records WHEN an account completed its activation step.
--
-- Data preservation: additive columns only; every pre-existing row is
-- backfilled to a safe default ('email_password' channel accounts were
-- already usable, so they are treated as activated at creation time).
-- ============================================================================

BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS activated_at TIMESTAMP WITH TIME ZONE;

-- Legacy email/password accounts: the register endpoint issued them a live
-- session immediately; treat them as activated so the rider flow never asks
-- them to redo consent that predates this column. Phone-OTP accounts start
-- un-activated and flip on via POST /api/v1/auth/onboarding/complete after
-- required agreements are accepted.
UPDATE users
SET onboarding_complete = true,
    activated_at = COALESCE(created_at, NOW())
WHERE COALESCE(created_via, 'email_password') <> 'phone_otp'
  AND activated_at IS NULL;

-- Partial index: cheap lookup of accounts still awaiting activation.
CREATE INDEX IF NOT EXISTS idx_users_not_activated
ON users(id) WHERE onboarding_complete = false;

COMMENT ON COLUMN users.onboarding_complete IS 'True once the account accepted required legal agreements (rider activation); optional profile fields may still be empty.';
COMMENT ON COLUMN users.activated_at IS 'When the account completed activation (consent acceptance); NULL until then.';

COMMIT;
