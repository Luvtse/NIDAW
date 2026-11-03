-- ============================================================================
-- 031_down — reverse 031_phone_identity
-- Restores NOT NULL constraints only if no NULL values were introduced by
-- phone-OTP registrations; otherwise fails loudly rather than destroying
-- data (choose/delete conflicting rows before re-applying the old schema).
-- ============================================================================

BEGIN;

DROP INDEX IF EXISTS uq_users_active_phone;

ALTER TABLE users DROP COLUMN IF EXISTS phone_verified_at;
ALTER TABLE users DROP COLUMN IF EXISTS created_via;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE email IS NULL) THEN
        RAISE EXCEPTION 'cannot restore users.email NOT NULL: phone-only accounts exist (email IS NULL)';
    END IF;
    IF EXISTS (SELECT 1 FROM users WHERE password_hash IS NULL) THEN
        RAISE EXCEPTION 'cannot restore users.password_hash NOT NULL: phone-only accounts exist (password_hash IS NULL)';
    END IF;
    IF EXISTS (SELECT 1 FROM users WHERE full_name IS NULL) THEN
        RAISE EXCEPTION 'cannot restore users.full_name NOT NULL: accounts with unset name exist';
    END IF;
END $$;

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;
ALTER TABLE users ALTER COLUMN full_name SET NOT NULL;

COMMIT;
