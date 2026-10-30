# Logix Load-Matching Schema Contract — Open Blocker

**Status: unresolved; do not enable the load-matching workflow in production.**

## Current architecture boundary

The load-matching application service now depends on a `CarrierRepository` port. PostgreSQL queries live in `infrastructure/postgres/carrier_repository.go`, including explicit query, scan, and row-iteration error handling. Unit tests cover application behavior with a stub repository. This separation does not validate the underlying table schema or justify runtime activation.

## Evidence from this repository

- `services/api/internal/modules/logix/application/services/load_matcher.go` issues SQL against `carriers`, selecting `id`, `company_name`, `mc_number`, `fleet_size`, `equipment_types`, `service_areas`, `rating`, `on_time_rate`, `insurance_amount`, and `status`.
- The candidate query assumes `status = 'active'`, country strings are members of `service_areas`, `equipment_type` is a member of `equipment_types`, and `insurance_amount >= 1000000`.
- The same file issues a second query against `carriers` by `id`.
- A repository-wide search of `data/migrations/postgres/*.sql` and source files found no `CREATE TABLE`/`ALTER TABLE` migration evidence for `carriers` or `loads`. The current load-matcher implementation receives a `*entities.Load`; it does not itself query a `loads` table.
- The customs adapter references `customs_declarations` and `shipments`, which also have no matching table definitions in the checked-in PostgreSQL migration chain. This is a broader Logix schema-readiness concern, not evidence that those tables are absent from every deployed database.
- No active runtime call site for `LoadMatcher.FindBestCarrier` was found in the inspected repository checkpoint.

## Required work before activation

1. Establish the authoritative schema source: checked-in migrations, an explicitly owned external schema, or a documented provisioning process. Do not infer table definitions from the Go `Scan` order alone.
2. Record ownership and migration/versioning responsibility for `carriers`, `loads` (if persisted), `customs_declarations`, and `shipments`.
3. Compare column types, nullability, enum/status values, array representation, indexes, and transaction behavior with the SQL and domain entities.
4. Add a repository-level contract test and PostgreSQL integration test against a clean database migrated from the authoritative chain.
5. Wire the matcher only after the schema contract and its transaction/publication semantics are validated; add tests for no candidates, query/scan failures, score ordering/ties, and outbox failure.

## Guardrail

The schema ownership inventory reports SQL identifiers used by Logix without matching migration evidence. This report is lexical evidence and can produce false positives for CTEs or database-managed objects; it must be reviewed alongside migration and deployment ownership. It is not a substitute for querying a live PostgreSQL catalog.
