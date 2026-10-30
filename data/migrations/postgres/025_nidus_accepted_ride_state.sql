BEGIN;

DROP INDEX IF EXISTS uq_rides_active_driver;
CREATE UNIQUE INDEX uq_rides_active_driver
    ON rides (driver_id)
    WHERE driver_id IS NOT NULL
      AND status IN ('requested', 'searching', 'matched', 'accepted', 'driver_en_route', 'in_progress');

COMMIT;
