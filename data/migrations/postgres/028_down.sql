-- Rollback for 028_nidus_stop_charges.sql.
-- Destructive by design: drops the stop-charge table and its index. The FK
-- from ride_stop_charges to ride_stops means dropping this table leaves the
-- stops themselves untouched (they belong to migration 012).

BEGIN;

DROP INDEX IF EXISTS idx_ride_stop_charges_ride;
DROP TABLE IF EXISTS ride_stop_charges;

COMMIT;
