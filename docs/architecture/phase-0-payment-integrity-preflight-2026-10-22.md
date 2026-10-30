# Phase 0 — Payment integrity migration preflight (2026-10-22)

## Objective

Improve safety before applying PostgreSQL migrations `015_payment_integrity.sql` and `016_payment_integrity_base.sql`, which add a unique idempotency-key index and a refunded-amount constraint alongside payment tables and indexes.

## Finding

The unique index `uq_transactions_idempotency_key` can fail if an existing `transactions` table contains multiple rows with the same `metadata->>'idempotency_key'`. Migration 016 can also fail to add `chk_transactions_refunded_within_amount` when existing rows have negative `refunded_amount` or a refunded total above the original charge. A non-positive legacy charge amount can also violate the declared transaction amount check on newly created tables, and duplicate pending refunds would violate the intended invariant if a `payment_refunds` table already exists.

The repository comments already identify duplicate idempotency keys as a deployment risk, but the migration flow did not provide a dedicated read-only preflight command to detect these data conditions before attempting the schema transaction.

## Change

Added `scripts/migrations/preflight-payment-integrity.sh`.

- Connects to the configured database using the existing `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and optional `DB_PASSWORD` environment variables.
- Uses a read-only PostgreSQL `DO` block to count duplicate idempotency keys, invalid refund totals, non-positive charge amounts, and duplicate pending refunds when the relevant tables exist.
- Fails with a clear exception if any blocking condition is found.
- Does not alter schema or data. It deliberately does not automatically delete, merge, or rewrite payment records; any remediation must be reviewed and auditable.

Added `scripts/migrations/tests/preflight-payment-integrity-test.sh` to verify the script invokes the expected read-only checks, contains no schema/data mutation statements, and propagates database command failures.

## Validation

Passed:

- Bash syntax check for the new preflight and its test.
- New preflight shell regression test using a mocked `psql` executable.
- Existing migration tests: `migrate-up-test.sh`, `migrate-down-test.sh`, `migrate-up-atomic-test.sh`, and `migrate-up-real-wrappers-test.sh`.

Not completed:

- No `psql`, PostgreSQL server, Docker, or Podman executable is available in this environment; the preflight SQL was not executed against PostgreSQL.
- Mocked tests verify shell orchestration and expected query content, not SQL syntax or query behavior against real data.
- No production database was inspected, so the presence or count of these anomalies is unknown.

## Recommended use

Before applying migrations 015/016 to an existing environment, run the preflight with that environment's approved connection settings. If it fails, preserve the reported counts and investigate the affected rows under the payment data-retention and audit policy. Do not automatically pick a “winner” for duplicate payment claims; reconcile each key against provider references and authoritative settlement evidence first.

## Acceptance status

This reduces deployment uncertainty but does not close Phase 0. Real PostgreSQL execution, representative upgrade testing, schema comparison, migration backup/restore verification, and the remaining route/client/deployment acceptance work are still required.
