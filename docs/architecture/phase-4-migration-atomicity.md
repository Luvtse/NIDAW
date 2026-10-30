# Phase 4 — Migration atomicity and schema evidence

## Change delivered

The migration runner now submits each eligible migration and its `schema_migrations` ledger row in a single PostgreSQL transaction. For legacy SQL files with top-level `BEGIN` and `COMMIT`, the runner creates a temporary normalized copy that removes only those transaction-control lines, appends the ledger insert, and executes the combined script with `psql --single-transaction`. Checked-in historical migration files and their checksums remain unchanged.

This closes a failure window where a migration could commit successfully and then fail while writing its ledger record, leaving a future run unable to distinguish the committed schema change from an unapplied migration.

## Validation

- `scripts/migrations/tests/migrate-up-atomic-test.sh` uses a mocked `psql` to assert that the migration SQL and ledger insert are submitted together under `--single-transaction`, and that top-level transaction markers are removed from the temporary script.
- Existing migration-runner tests continue to validate dry-run, forbidden target, checksum drift, and history-gap behavior.
- This is a runner-level regression test, not a substitute for applying migrations against a real PostgreSQL instance.

## Known limitations and next validation

- Real PostgreSQL validation is still required for migrations 001–017, especially payment schema migrations 015/016 and any legacy database shape.
- PostgreSQL statements that cannot run in a transaction must be explicitly identified before adopting this runner strategy for them. Current migration files should be reviewed for commands such as `CREATE INDEX CONCURRENTLY` before release.
- Historical migration ordering/comments around 015 and 016 remain inconsistent: 015 currently creates a compatible `transactions` base itself, while 016 adds reconciliation/payout tables and repeats guarded column definitions. A schema-diff review is needed before consolidating these files; do not rewrite already-applied migrations.
- Rollback remains unsupported without reviewed numbered down migrations; recovery should use forward fixes or a verified restore procedure.
