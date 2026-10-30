#!/usr/bin/env bash
set -euo pipefail

# Read-only checks for data that could prevent migrations 015/016 from adding
# payment-integrity indexes/constraints. This script never changes the schema.
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-nidaw}"
DB_USER="${DB_USER:-nidaw}"
DB_PASSWORD="${DB_PASSWORD:-}"

if [[ -n "$DB_PASSWORD" ]]; then
    export PGPASSWORD="$DB_PASSWORD"
fi
command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required for payment-integrity preflight." >&2
    exit 2
}

psql -X -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'SQL'
DO $$
DECLARE
    duplicate_idempotency_keys BIGINT := 0;
    invalid_refund_totals BIGINT := 0;
    invalid_charge_amounts BIGINT := 0;
    duplicate_pending_refunds BIGINT := 0;
BEGIN
    IF to_regclass('public.transactions') IS NOT NULL THEN
        EXECUTE $q$
            SELECT count(*) FROM (
                SELECT metadata->>'idempotency_key' AS idempotency_key
                FROM public.transactions
                WHERE metadata ? 'idempotency_key'
                GROUP BY metadata->>'idempotency_key'
                HAVING count(*) > 1
            ) duplicates
        $q$ INTO duplicate_idempotency_keys;

        EXECUTE $q$
            SELECT count(*) FROM public.transactions
            WHERE refunded_amount < 0 OR refunded_amount > amount
        $q$ INTO invalid_refund_totals;

        EXECUTE $q$
            SELECT count(*) FROM public.transactions WHERE amount <= 0
        $q$ INTO invalid_charge_amounts;
    ELSE
        RAISE NOTICE 'public.transactions does not exist yet; transaction-data checks skipped.';
    END IF;

    IF to_regclass('public.payment_refunds') IS NOT NULL THEN
        EXECUTE $q$
            SELECT count(*) FROM (
                SELECT transaction_id
                FROM public.payment_refunds
                WHERE status = 'pending'
                GROUP BY transaction_id
                HAVING count(*) > 1
            ) duplicates
        $q$ INTO duplicate_pending_refunds;
    ELSE
        RAISE NOTICE 'public.payment_refunds does not exist yet; pending-refund check skipped.';
    END IF;

    RAISE NOTICE 'Payment integrity preflight counts: duplicate idempotency keys=%, invalid refund totals=%, non-positive charge amounts=%, duplicate pending refunds=%',
        duplicate_idempotency_keys, invalid_refund_totals, invalid_charge_amounts, duplicate_pending_refunds;

    IF duplicate_idempotency_keys > 0 OR invalid_refund_totals > 0
       OR invalid_charge_amounts > 0 OR duplicate_pending_refunds > 0 THEN
        RAISE EXCEPTION 'Payment integrity preflight failed. Resolve the reported data anomalies using a reviewed, auditable remediation before applying migrations 015/016.';
    END IF;
END $$;
SQL

echo "Payment integrity preflight passed; no blocking anomalies were found by the checks above."
