-- ============================================================================
-- 033_down — reverse 033_device_sessions
-- Drops the persistent device-session table and its indexes. Revocable data
-- only; no other module depends on auth_device_sessions.
-- ============================================================================

BEGIN;

DROP INDEX IF EXISTS uq_device_sessions_active_hash;
DROP INDEX IF EXISTS idx_device_sessions_family;
DROP INDEX IF EXISTS idx_device_sessions_user;
DROP TABLE IF EXISTS auth_device_sessions;

COMMIT;
