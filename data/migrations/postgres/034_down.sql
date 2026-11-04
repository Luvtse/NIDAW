-- ============================================================================
-- 034_down.sql — revert driver substitute relationships (Phase 7)
-- ============================================================================

BEGIN;

DROP INDEX IF EXISTS idx_substitute_active_lookup;
DROP INDEX IF EXISTS idx_substitute_by_user;
DROP INDEX IF EXISTS idx_substitute_by_primary;
DROP INDEX IF EXISTS uq_substitute_live_relationship;

DROP TABLE IF EXISTS driver_substitute_relationships;

COMMIT;
