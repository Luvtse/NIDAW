-- ============================================================================
-- NIDAW FARE INTEGRITY — Phase 1: immutable booking fare snapshot.
--
-- The accepted booking IS the pricing contract. ride_fare_snapshots stores
-- the authoritative, server-frozen quote (original endpoints, contractual
-- distance/duration, itemized components in INTEGER ETB SANTIM, pinned
-- pricing-config and duration-rule versions). Actual GPS metrics live on the
-- rides row for operations only and can never rewrite these numbers.
--
-- Money columns are BIGINT santim (1 ETB = 100 santim) with CHECK > 0 on the
-- quoted total; currency is CHAR(3) DEFAULT 'ETB' with a hard CHECK so no
-- other currency can ever be persisted into a contract row.
--
-- Idempotency: UNIQUE(idempotency_key) lets the request path re-persist the
-- same snapshot safely (ON CONFLICT DO NOTHING + read-back), which is what
-- repository CreateSnapshot relies on.
--
-- Immutability: a BEFORE UPDATE trigger aborts any attempt to modify a
-- frozen row. Corrections happen through NEW approved additions (stops) or a
-- NEW snapshot revision after an explicitly rider-approved amendment — never
-- by editing this table. DELETE remains available to operators/retention
-- jobs; it is not exposed by any application code path.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS ride_fare_snapshots (
    id                    UUID        PRIMARY KEY,
    ride_id               UUID        NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    idempotency_key       TEXT        NOT NULL,

    -- Contract geometry: the ORIGINAL pickup/dropoff that produced the quote.
    pickup_lat            DOUBLE PRECISION NOT NULL,
    pickup_lng            DOUBLE PRECISION NOT NULL,
    dropoff_lat           DOUBLE PRECISION NOT NULL,
    dropoff_lng           DOUBLE PRECISION NOT NULL,
    pickup_address        TEXT,
    dropoff_address       TEXT,

    -- Frozen trip shape (never overwritten by actuals).
    contract_distance_km  DOUBLE PRECISION NOT NULL CHECK (contract_distance_km >= 0),
    contract_duration_min INTEGER          NOT NULL CHECK (contract_duration_min >= 1),

    -- Itemized breakdown, integer ETB santim.
    base_fare_santim      BIGINT NOT NULL CHECK (base_fare_santim     >= 0),
    distance_fare_santim  BIGINT NOT NULL CHECK (distance_fare_santim >= 0),
    time_fare_santim      BIGINT NOT NULL CHECK (time_fare_santim     >= 0),
    surge_amount_santim   BIGINT NOT NULL CHECK (surge_amount_santim  >= 0),
    minimum_fare_santim   BIGINT NOT NULL CHECK (minimum_fare_santim  >= 0),
    gross_fare_santim     BIGINT NOT NULL CHECK (gross_fare_santim    >= 0),
    quoted_total_santim   BIGINT NOT NULL CHECK (quoted_total_santim  >  0),

    -- Frozen rules and rates (rates are major-unit ETB per km / per minute —
    -- deliberately distinct from the santim totals above).
    ride_type             TEXT    NOT NULL,
    distance_rate_per_km  DOUBLE PRECISION NOT NULL CHECK (distance_rate_per_km >= 0),
    time_rate_per_minute  DOUBLE PRECISION NOT NULL CHECK (time_rate_per_minute >= 0),
    surge_multiplier      DOUBLE PRECISION NOT NULL CHECK (surge_multiplier >= 1),
    surge_reason          TEXT,
    minutes_per_km        DOUBLE PRECISION NOT NULL CHECK (minutes_per_km > 0),

    -- Version pins: historical rides keep the rule set they were quoted with.
    pricing_config_version TEXT NOT NULL,
    duration_rule_version  TEXT NOT NULL,

    currency              CHAR(3) NOT NULL DEFAULT 'ETB' CHECK (currency = 'ETB'),
    frozen_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_ride_fare_snapshots_idempotency UNIQUE (idempotency_key),
    CONSTRAINT uq_ride_fare_snapshots_ride        UNIQUE (ride_id)
);

CREATE INDEX IF NOT EXISTS idx_ride_fare_snapshots_ride
    ON ride_fare_snapshots (ride_id);

-- ---------------------------------------------------------------------------
-- Immutability guard.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION nidus_enforce_fare_snapshot_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'ride_fare_snapshots rows are immutable fare contracts (ride %, snapshot %); create a new approved revision instead',
        OLD.ride_id, OLD.id
        USING ERRCODE = 'check_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_fare_snapshots_immutable ON ride_fare_snapshots;
CREATE TRIGGER trg_ride_fare_snapshots_immutable
    BEFORE UPDATE ON ride_fare_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION nidus_enforce_fare_snapshot_immutability();

-- ---------------------------------------------------------------------------
-- Pointer on the rides row so every downstream consumer (dispatch payload,
-- receipt, ledger settlement, driver app) can locate THE one contract row for
-- a ride without guessing. Nullable: rides created before this migration have
-- no frozen snapshot and completion refuses them until reconciled (Phase 1
-- rollout note: backfill via the pricing service before enabling enforcement
-- in production traffic).
-- ---------------------------------------------------------------------------

ALTER TABLE rides
    ADD COLUMN IF NOT EXISTS fare_snapshot_id UUID REFERENCES ride_fare_snapshots(id) ON DELETE SET NULL;

COMMIT;
