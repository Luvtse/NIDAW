-- ============================================================================
-- NIDAW FARE INTEGRITY — Phase 2 follow-up: approved destination amendments.
--
-- ride_fare_snapshots keeps ONE contract row per ride (uq_ride_fare_snapshots_
-- ride from migration 027). A rider-approved mid-trip destination change is a
-- NEW contract revision, never an edit of the frozen original (§2.1), so the
-- amendment history needs its own table:
--
--   * destination_fare_amendments stores every APPROVED amended quote as an
--     immutable snapshot revision keyed by amend:<ride_id>:<n>. The original
--     booking snapshot row in ride_fare_snapshots is left untouched forever.
--   * rides.fare_snapshot_id is repointed to the latest accepted amendment id
--     (see change_destination.go), so completion and settlement always read
--     THE current contract through exactly one pointer — requireContract's
--     fare_amount ↔ quoted_total_santim reconciliation applies unchanged to
--     amendments.
--   * Idempotency: UNIQUE(ride_id, seq) makes a retried confirmation land on
--     the same revision (ON CONFLICT DO NOTHING + read-back), and
--     UNIQUE(idempotency_key) matches the snapshot repository convention.
--   * Immutability: BEFORE UPDATE trigger aborts edits, mirroring 027.
--     Corrections to an amendment are newer amendments, never mutations.
--
-- Money columns are BIGINT ETB santim with the same CHECK shape as 027;
-- currency has a hard CHECK = 'ETB' so no other currency can ever be
-- persisted into an amendment row.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS destination_fare_amendments (
    id                    UUID        PRIMARY KEY,
    ride_id               UUID        NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    idempotency_key       TEXT        NOT NULL,
    seq                   INTEGER     NOT NULL CHECK (seq >= 1),

    -- Amendment geometry: the previous dropoff replaced and the new one the
    -- rider explicitly confirmed. Pickup stays the ORIGINAL contract pickup.
    prev_dropoff_lat      DOUBLE PRECISION NOT NULL,
    prev_dropoff_lng      DOUBLE PRECISION NOT NULL,
    dropoff_lat           DOUBLE PRECISION NOT NULL,
    dropoff_lng           DOUBLE PRECISION NOT NULL,
    dropoff_address       TEXT,

    -- Frozen amended trip shape (contractual, never actuals).
    contract_distance_km  DOUBLE PRECISION NOT NULL CHECK (contract_distance_km >= 0),
    contract_duration_min INTEGER          NOT NULL CHECK (contract_duration_min >= 1),

    -- Itemized breakdown, integer ETB santim (same shape as 027).
    base_fare_santim      BIGINT NOT NULL CHECK (base_fare_santim     >= 0),
    distance_fare_santim  BIGINT NOT NULL CHECK (distance_fare_santim >= 0),
    time_fare_santim      BIGINT NOT NULL CHECK (time_fare_santim     >= 0),
    surge_amount_santim   BIGINT NOT NULL CHECK (surge_amount_santim  >= 0),
    minimum_fare_santim   BIGINT NOT NULL CHECK (minimum_fare_santim  >= 0),
    gross_fare_santim     BIGINT NOT NULL CHECK (gross_fare_santim    >= 0),
    quoted_total_santim   BIGINT NOT NULL CHECK (quoted_total_santim  >  0),

    -- Frozen rules and rates (rates are major-unit ETB per km / per minute).
    ride_type             TEXT    NOT NULL,
    distance_rate_per_km  DOUBLE PRECISION NOT NULL CHECK (distance_rate_per_km >= 0),
    time_rate_per_minute  DOUBLE PRECISION NOT NULL CHECK (time_rate_per_minute >= 0),
    surge_multiplier      DOUBLE PRECISION NOT NULL CHECK (surge_multiplier >= 1),
    surge_reason          TEXT,
    minutes_per_km        DOUBLE PRECISION NOT NULL CHECK (minutes_per_km > 0),
    pricing_config_version   TEXT    NOT NULL,
    duration_rule_version    TEXT    NOT NULL,
    currency              CHAR(3) NOT NULL DEFAULT 'ETB' CHECK (currency = 'ETB'),

    -- Audit trail: who approved, when, and what the contract was before.
    approved_by           UUID        NOT NULL REFERENCES users(id),
    previous_quoted_santim BIGINT     NOT NULL CHECK (previous_quoted_santim > 0),
    approved_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_destination_fare_amendments_key UNIQUE (idempotency_key),
    CONSTRAINT uq_destination_fare_amendments_seq UNIQUE (ride_id, seq)
);

CREATE INDEX IF NOT EXISTS idx_destination_fare_amendments_ride
    ON destination_fare_amendments (ride_id);

-- ---------------------------------------------------------------------------
-- Immutability guard (mirrors 027): amendments are contracts, not drafts.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION nidus_enforce_destination_amendment_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'destination_fare_amendments rows are immutable approved revisions (ride %, amendment %); create a newer approved amendment instead',
        OLD.ride_id, OLD.id
        USING ERRCODE = 'check_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_destination_fare_amendments_immutable ON destination_fare_amendments;
CREATE TRIGGER trg_destination_fare_amendments_immutable
    BEFORE UPDATE ON destination_fare_amendments
    FOR EACH ROW
    EXECUTE FUNCTION nidus_enforce_destination_amendment_immutability();

COMMIT;
