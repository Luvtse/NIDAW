-- Rollback for 019_haven_room_inventory.sql.
-- This removes the inventory ledger and its reservation counts; apply only after
-- confirming Haven bookings no longer rely on this inventory data.
DROP TABLE IF EXISTS hotel_room_inventory;
