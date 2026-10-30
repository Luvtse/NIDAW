# Phase 0 — Migration runner regression validation (2026-10-22)

## Scope

This continuation validates the migration runner's transaction normalization using the actual payment-integrity migrations `015_payment_integrity.sql` and `016_payment_integrity_base.sql`. It does not execute SQL against PostgreSQL.

## Change made

Added `scripts/migrations/tests/migrate-up-real-wrappers-test.sh`. The test copies migrations 015 and 016 into an isolated temporary migration directory, renumbers only those temporary copies, and runs them through `scripts/migrations/migrate-up.sh` with a mocked `psql` executable. For both migration files, it asserts:

- the runner invokes `psql --single-transaction`;
- top-level `BEGIN`/`START TRANSACTION` and `COMMIT` statements are removed from the temporary transaction script;
- the migration statements and `schema_migrations` ledger insert are present;
- both migrations are processed in lexical order.

The checked-in migration files are not modified by this test. The production runner removes only top-level transaction-control lines from its temporary copy and places schema changes plus the ledger insert under `--single-transaction`.

## Verification results

Passed in this environment:

- `scripts/migrations/tests/migrate-down-test.sh`
- `scripts/migrations/tests/migrate-up-atomic-test.sh`
- `scripts/migrations/tests/migrate-up-real-wrappers-test.sh`
- `scripts/migrations/tests/migrate-up-test.sh`
- `bash -n scripts/migrations/migrate-up.sh scripts/migrations/migrate-down.sh scripts/migrations/tests/*.sh`

The new wrapper test explicitly reports that `psql` is mocked. These results verify runner control flow and SQL-file normalization only. They do not prove SQL validity, schema convergence, locking behavior, or rollback behavior on a real PostgreSQL server.

## Outstanding risks and acceptance actions

- PostgreSQL CLI/server is unavailable in this environment; test migrations 015/016 on a disposable database in both empty-schema and representative upgrade scenarios.
- Migration 015 and 016 both define overlapping `transactions` columns/objects. Static inspection suggests their `IF NOT EXISTS` pattern is intended to converge, but actual PostgreSQL convergence and constraints/index definitions must be compared after both possible application orders in an isolated test database.
- Confirm migration 015's unique idempotency index and refund uniqueness assumptions against existing production-like data before rollout; duplicate existing idempotency keys can prevent unique-index creation.
- Validate rollback/restore strategy and migration history checksums against a copy of a real migration ledger. Do not rewrite applied migration history to make tests pass.

## Phase status

Phase 0 remains open. This is a stronger mocked regression check, not a PostgreSQL-backed migration acceptance result and not authorization to advance dependent phases.
