-- ============================================================================
-- NIDAW FARE INTEGRITY — Phase 2: rider-approved stop charges & server-
-- authoritative stop timers.
--
-- Policy (stops-v1, encoded in domain/entities/stop_charge.go):
--   * Every intermediate stop becomes payable ONLY after the rider approves
--     its disclosed fixed fee (default Br 10.00 = 1000 santim, frozen per
--     approval).
--   * A stop whose SERVER-RECORDED dwell reaches 10 minutes additionally
--     incurs a waiting charge equal to 50% of the ORIGINAL booking fare —
--     computed on the frozen quoted total, never on fares that already
--     include other stop fees (non-compounding by construction).
--   * Drivers cannot create rider-requested stops or manipulate their start
--     times: every timestamp below is written by the API server clock
--     (DEFAULT NOW()), and the approve/update statements require the rider's
--     user id in the WHERE clause.
--
-- Money columns are BIGINT santim like migration 027; currency stays ETB via
-- CHECK. Idempotency: approvals are keyed UNIQUE(ride_id, seq) — a retried
-- approval can never mint a second fee for one stop.
--
-- Additive and backward-safe: rides without approved stops price exactly as
-- before; legacy ride_stops rows simply have no charge record (the settlement
-- finalizer reads LEFT JOIN semantics through this table's absence).
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS ride_stop_charges (
    ride_id                 UUID        NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    seq                     SMALLINT    NOT NULL CHECK (seq BETWEEN 1 AND 3),

    -- Disclosure + approval (rider-only writes; server clock).
    stop_fee_santim         BIGINT      NOT NULL CHECK (stop_fee_santim >= 0),
    policy_version          TEXT        NOT NULL DEFAULT 'stops-v1',
    approved_by_rider       BOOLEAN     NOT NULL DEFAULT TRUE,
    approved_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Server-recorded stop window (auditable events). started_at is stamped
    -- when the driver confirms arrival at the APPROVED stop; ended_at when
    -- departure is recorded. Both stay NULL until they genuinely happen —
    -- nothing here is ever fabricated or backdated by a client.
    started_at              TIMESTAMPTZ,
    ended_at                TIMESTAMPTZ,

    -- Derived amounts, persisted so receipt/ledger read exact stored numbers
    -- instead of recomputing from clocks at settlement time.
    duration_minutes        INTEGER     NOT NULL DEFAULT 0 CHECK (duration_minutes >= 0),
    waiting_eligible        BOOLEAN     NOT NULL DEFAULT FALSE,
    waiting_charge_santim   BIGINT      NOT NULL DEFAULT 0 CHECK (waiting_charge_santim >= 0),

    currency                CHAR(3)     NOT NULL DEFAULT 'ETB' CHECK (currency = 'ETB'),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (ride_id, seq),
    -- A stop charge must reference a stop that actually exists on the ride.
    CONSTRAINT fk_ride_stop_charges_stop FOREIGN KEY (ride_id, seq)
        REFERENCES ride_stops (ride_id, seq) ON DELETE CASCADE
);

COMMENT ON TABLE ride_stop_charges IS
    'Phase 2: rider-approved stop fees with server-measured dwell and non-
     compounding 50%-of-original-fare waiting charges (policy stops-v1).';
COMMENT ON COLUMN ride_stop_charges.stop_fee_santim IS
    'Fixed per-stop fee DISCLOSED TO AND APPROVED BY the rider before the stop
     became payable, frozen at approval time (integer ETB santim).';
COMMENT ON COLUMN ride_stop_charges.waiting_charge_santim IS
    'Waiting charge earned when the server-recorded dwell crossed the 10-minute
     threshold: exactly 50% of the ORIGINAL frozen booking fare, rounded half-up
     to the santim. Never computed on a base that includes other stop charges.';
COMMENT ON COLUMN ride_stop_charges.started_at IS
    'Server clock stamp when the stop timer started (driver arrival at an
     APPROVED stop). NULL until it genuinely happened; drivers cannot set it.';

CREATE INDEX IF NOT EXISTS idx_ride_stop_charges_ride
    ON ride_stop_charges (ride_id);

COMMIT;
