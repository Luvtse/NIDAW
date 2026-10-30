# Phase 3 — Migration and Domain-Boundary Guardrails

## Implemented in this checkpoint

### Migration runner

- `--dry-run` no longer creates `schema_migrations`; it checks database connectivity and only reads the ledger.
- Explicit targets must be three-digit versions that exist. Production cannot explicitly target the development seed migration (003) or test-only fault-injection migration (017).
- Production excludes 003 seed data; the migration's own header explicitly permits it in development/staging. Migration 017 fault-injection schema is excluded outside test/CI.
- Pending migration selection checks the ledger per version and stops if an eligible historical migration is missing before a later version recorded as applied, instead of silently repairing the schema out of order.
- Applied migration checksums are compared when a recorded checksum exists. A mismatch stops the runner and directs maintainers to add a forward migration instead of editing history.
- SQL files that contain their own `BEGIN`/`COMMIT` are not wrapped in a second psql transaction. Files without an explicit transaction use psql's single-transaction wrapper.
- A failed pending-migration calculation stops execution instead of being swallowed by process substitution.
- The migration runner has mocked-database regression tests for dry-run behavior, target bounds, production exclusions, and applied-checksum drift.
- Rollback validates `--steps` as a positive integer and checks for matching down-migration files before prompting or executing SQL. Since no numbered down migrations are supplied today, it fails early with a recovery/forward-migration recommendation rather than suggesting rollback is available.

### Product module boundaries

- Added `scripts/architecture/check-go-product-boundaries.py` and wired it into backend CI.
- The check rejects direct Go imports from one of the five product modules into another product's private package.
- Current result: no direct product-to-product Go imports detected.
- Only `nidus`, `logix`, and `corpus` exist as product module directories. `haven` and `vorax` remain unimplemented as Go modules; this guard does not claim otherwise.

## Validation performed

- `bash -n scripts/migrations/migrate-up.sh scripts/migrations/tests/migrate-up-test.sh`: passed.
- `scripts/migrations/tests/migrate-up-test.sh`: passed with a mocked `psql` binary.
- `scripts/migrations/tests/migrate-down-test.sh`: passed with a mocked `psql` binary.
- Historical result at that checkpoint: `python3 scripts/architecture/check-go-product-boundaries.py` returned 0 while reporting Haven/Vorax missing. The 2026-10-23 Phase 0 gate-hardening change intentionally makes those missing modules a non-zero CI blocker; see `phase-0-product-module-gate-hardening-2026-10-23.md`.
- Workflow YAML parsing is validated separately in the local repository checks.

## Limitations and remaining risks

- The migration tests use a mock database client; they do not execute SQL against PostgreSQL.
- Existing migration ledger rows with a NULL/empty checksum are tolerated for compatibility, so they are not retroactively verified.
- `015_payment_integrity.sql` and `016_payment_integrity_base.sql` still overlap intentionally on the `transactions` schema. They need fresh-database and upgrade-path tests against PostgreSQL before production use.
- Migration SQL application and ledger insertion are separate database operations. The SQL is intended to be idempotent, but a real PostgreSQL failure-injection test is still required.
- The product boundary check examines static Go imports only. It does not prove ownership boundaries for SQL, HTTP routes, events, shared tables, or runtime dependency injection.
- This checkpoint does not certify the repository for production deployment.
