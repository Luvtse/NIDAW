-- ============================================================================
-- 031_phone_identity
-- Phone-number-first identity support (Auth roadmap Phase 2).
--
-- Rationale: riders and drivers authenticate with phone + OTP. Email and
-- password become optional recovery/contact fields, so their NOT NULL
-- constraints must be relaxed without touching existing rows. Verification
-- state for the mandatory phone factor is recorded alongside the existing
-- email_verified flag.
--
-- Data preservation: ALTER COLUMN ... DROP NOT NULL keeps all existing data.
-- Existing UNIQUE(phone) constraint already prevents duplicate/conflicting
-- phone identities; a partial index reinforces active-identity lookups.
-- ============================================================================

BEGIN;

ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

-- full_name becomes optional at registration time (rider flow allows
-- "skip and complete later"); preserve any existing value semantics by
-- relaxing NOT NULL as well.
ALTER TABLE users ALTER COLUMN full_name DROP NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_via VARCHAR(32) NOT NULL DEFAULT 'email_password';

-- Every pre-existing account was provisioned through the email/password
-- register endpoint; mark them accordingly so phone-OTP flows can detect
-- legacy accounts and never silently merge identities.
UPDATE users SET created_via = 'email_password' WHERE created_via IS NULL OR created_via = '';

-- Accounts that already completed phone-based verification keep their state;
-- legacy accounts have no proof of phone possession yet.

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_active_phone ON users(phone) WHERE status <> 'deleted';

COMMENT ON COLUMN users.phone_verified_at IS 'When the user last proved possession of the phone number via OTP; NULL means unverified.';
COMMENT ON COLUMN users.created_via IS 'Provisioning channel of the account: email_password | phone_otp.';
COMMENT ON COLUMN users.password_hash IS 'Optional bcrypt hash; NULL for phone-only accounts until a password is set.';

COMMIT;
