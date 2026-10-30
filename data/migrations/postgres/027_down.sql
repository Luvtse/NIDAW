-- Rollback for 027_nidus_fare_snapshot.sql.
-- Drops the pointer column first (it references the snapshot table), then the
-- table and its immutability trigger/function. Destructive by design: use
-- only when fully reverting Phase 1.

BEGIN;

ALTER TABLE rides DROP COLUMN IF EXISTS fare_snapshot_id;

DROP TRIGGER IF EXISTS trg_ride_fare_snapshots_immutable ON ride_fare_snapshots;
DROP FUNCTION IF EXISTS nidus_enforce_fare_snapshot_immutability();
DROP TABLE IF EXISTS ride_fare_snapshots;

COMMIT;
