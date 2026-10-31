-- Rollback for 030_nidus_destination_fare_amendments.sql.
-- Destructive by design: drops the amendment history table with its
-- immutability trigger/function. rides.fare_snapshot_id pointers that were
-- repointed to amendments remain valid UUIDs but may reference amendment ids
-- no longer present; reconcile before re-running forward migrations if this
-- rollback is used in an environment that accepted amendments.

BEGIN;

DROP TRIGGER IF EXISTS trg_destination_fare_amendments_immutable ON destination_fare_amendments;
DROP FUNCTION IF EXISTS nidus_enforce_destination_amendment_immutability();
DROP TABLE IF EXISTS destination_fare_amendments;

COMMIT;
