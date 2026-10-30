-- Haven inventory is date-scoped so concurrent bookings cannot over-reserve rooms.
-- Inventory is deliberately not fabricated for existing hotels: an operator must
-- provision each bookable hotel/date before bookings can be accepted.
CREATE TABLE IF NOT EXISTS hotel_room_inventory (
    hotel_id uuid NOT NULL REFERENCES hotels(id) ON DELETE CASCADE,
    inventory_date date NOT NULL,
    total_rooms integer NOT NULL CHECK (total_rooms > 0),
    reserved_rooms integer NOT NULL DEFAULT 0 CHECK (reserved_rooms >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (hotel_id, inventory_date),
    CHECK (reserved_rooms <= total_rooms)
);

CREATE INDEX IF NOT EXISTS idx_hotel_room_inventory_date
    ON hotel_room_inventory (inventory_date, hotel_id);
