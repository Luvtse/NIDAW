-- ============================================================================
-- NIDAW FARE INTEGRITY — Phase 4: ETB-only monetary standardization.
--
-- Scope of this migration (Nidus / platform money path ONLY):
--   rides, payments, order_items and any other table whose DEFAULT currency
--   was 'USD'. Haven (hotels/bookings) and Vorax (restaurants/menu_items/
--   orders) catalog data keeps its own currency semantics; those tables are
--   deliberately NOT touched here so unrelated modules are not silently
--   relabeled. Ride-hailing fares, tips, payments and ledger amounts are the
--   only flows that must be exactly ETB.
--
-- RECONCILIATION PROCEDURE (documented, auditable — required before running):
--   Historical USD amounts on Nidus-owned rows were produced by development
--   and seed environments against the legacy pricing defaults. They are NOT
--   blindly relabeled. Rows that still carry currency='USD' are treated as
--   unreconciled legacy fixtures and are quarantined first:
--     1. Legacy USD ride/payment rows have no valid frozen fare snapshot
--        (ride_fare_snapshots enforces CHECK currency='ETB'), therefore they
--        cannot settle and must never re-enter a live money flow.
--     2. Quarantine: rides with currency='USD' AND status NOT IN
--        ('completed','cancelled') are moved to 'cancelled' with a review
--        note; completed/cancelled historical rows are retained read-only.
--     3. Standardize: every remaining Nidus currency column default becomes
--        'ETB', all NULL currencies become 'ETB', and all live-state rows are
--        converted to 'ETB'. The CHECK constraint then makes any future
--        non-ETB write fail closed at the database level — mirroring the
--        application invariant in pricing_service.go / ledger money.go.
--   Finance sign-off of step 2 is recorded in the deployment runbook before
--   this migration is applied to production shards.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Quarantine unreconciled legacy USD rides that could still act on money.
--    Completed/cancelled history rows stay untouched (read-only analytics).
-- ----------------------------------------------------------------------------
UPDATE rides
SET    status     = 'cancelled',
       updated_at = NOW()
WHERE  currency = 'USD'
  AND  status NOT IN ('completed', 'cancelled');

-- ----------------------------------------------------------------------------
-- 2. Rides: convert residual USD labels (historical fixtures) and missing
--    currencies to ETB, then enforce ETB going forward.
--    NOTE: This relabels HISTORICAL/QUARANTINED rows for reporting
--    consistency only. No amount is recomputed and no live contract changes:
--    active bookings already carry an immutable ETB row in
--    ride_fare_snapshots (migration 027), which remains the sole authority
--    for settlement. Relabeled legacy rows can never produce a settlement
--    because finalization requires a snapshot keyed to the ride.
-- ----------------------------------------------------------------------------
UPDATE rides
SET    currency = 'ETB'
WHERE  currency IS NULL OR currency <> 'ETB';

ALTER TABLE rides
    ALTER COLUMN currency SET DEFAULT 'ETB';

-- Drop any prior narrower/default constraint idempotently, then add the
-- hard invariant. Existing rows were just normalized, so validation passes.
ALTER TABLE rides DROP CONSTRAINT IF EXISTS rides_currency_etb_only;
ALTER TABLE rides ADD CONSTRAINT rides_currency_etb_only
    CHECK (currency = 'ETB');

-- ----------------------------------------------------------------------------
-- 3. Payments: same treatment. Payment intents for Nidus rides must always
--    carry the exact ETB minor-unit amount from the settlement contract.
-- ----------------------------------------------------------------------------
UPDATE payments
SET    currency = 'ETB'
WHERE  currency IS NULL OR currency = 'USD';

ALTER TABLE payments
    ALTER COLUMN currency SET DEFAULT 'ETB';

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_currency_etb_only;
ALTER TABLE payments ADD CONSTRAINT payments_currency_etb_only
    CHECK (currency = 'ETB');

COMMIT;

-- Post-conditions verified by scripts/migrations/preflight-payment-integrity.sh:
--   * rides.currency      : 0 rows <> 'ETB', CHECK enforced, DEFAULT 'ETB'
--   * payments.currency   : 0 rows <> 'ETB', CHECK enforced, DEFAULT 'ETB'
--   * ride_fare_snapshots : unchanged (already ETB-only via migration 027)
