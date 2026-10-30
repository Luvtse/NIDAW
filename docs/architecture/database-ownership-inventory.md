# NIDAW Database Ownership Inventory (Preliminary)

## Status

This is a preliminary ownership map derived from migration DDL and code references. It is not a statement that the schema is safe or that every table is used in production. Table ownership remains provisional until all SQL reads/writes, ORM models, production migration history, and deployed schemas are reconciled.

## Migration inventory

- PostgreSQL: `data/migrations/postgres/001_initial_schema.sql` through `017_t5_fault_injection.sql`.
- TimescaleDB: `data/migrations/timescale/001_hypertables.sql`.
- Additional schema drafts: `database/PostgreSQL Schema (Sharded via Citus).sql`, `database/TimescaleDB Hypertable for GPS Tracking.sql`.
- Seed assets: `data/seeds/sample-data.sql`, plus `003_seed_data.sql`.

The numbered migrations are lexically ordered but migration runner behavior, migration ledger/idempotency, rollback support, and deployed execution history have not yet been verified. Migrations `015_payment_integrity.sql` and `016_payment_integrity_base.sql` both define or alter `transactions` and related payment structures; their overlap must be checked before changing order or removing either file. `017_t5_fault_injection.sql` creates a fault-injection table and requires confirmation that it is restricted to safe test environments.

## Preliminary table ownership

| Table / table family | Candidate owner | Evidence | Confidence / action |
|---|---|---|---|
| `users` | Identity | Initial schema; auth/identity modules exist | Medium; map actual writer and identity source of truth. |
| `drivers` | Nidus / driver identity profile | Initial schema; Nidus driver workflows | Medium; separate identity credentials from driver operational profile. |
| `rides`, `ride_stops`, `ride_matched_events`, `ride_completed_events`, scheduled-ride fields | Nidus | Migrations 001, 005, 008, 012, 013, 014 | High candidate; verify every write path and transition constraint. |
| `driver_locations`, `ride_metrics` | Nidus / telemetry infrastructure | Timescale migration and GPS schema | Medium; establish retention, privacy, and access policy. |
| `hotels`, `bookings` | Haven | Initial schema and legacy Citus schema | Low-to-medium; no Haven Go module found, so runtime ownership is unproven. |
| `restaurants`, `menu_items`, `orders`, `order_items` | Vorax | Initial schema and analytics order references | Low-to-medium; no Vorax Go module found, so runtime ownership is unproven. |
| `payments` | Payment processing | Initial schema | Medium; distinguish from `transactions` and payment-method metadata. |
| `payment_methods` | Payments / payment-method capability | Migration 007 and `modules/payments` PostgreSQL repository | High candidate; verify uniqueness constraint and user ownership checks. |
| `transactions`, `payment_refunds`, `reconciliation_reports`, `payouts` | Payment processing | Migrations 015/016 and `modules/payment` reconciliation SQL | High candidate; review overlapping migrations and provider idempotency. |
| `ledger_transactions`, `user_balances`, `topup_requests`, `withdrawal_requests`, `escrow_holds`, `ride_disputes`, `fraud_flags`, `audit_log` | Ledger/Finance | Migration 004 and ledger module | High candidate; confirm `audit_log` is not shared across incompatible owners. |
| `promo_codes`, `promo_redemptions` | Promotions | Migration 009 and promotions module | High candidate; verify redemption uniqueness and race protections. |
| `legal_documents`, `user_consents`, `consent_audit_log` | Legal/Consent | Initial schema and legal module | Medium; define retention and access control. |
| `corporate_bookings`, `corporate_employees`, corporate policy/account tables | Corpus | `modules/corpus/application/commands/create_booking.go` directly queries/inserts these tables; entity model exists | High candidate for booking records; inventory all corporate tables and enforce tenant isolation. |
| `api_metrics`, `business_metrics` | Observability/Analytics | Timescale migration | Medium; clarify operational vs product-owned metrics. |
| `t5_fault_injection` | Test/operations only | Migration 017 | High risk until environment gating and access permissions are verified. |

## Ownership and safety issues to resolve

1. Several product families (`hotels`, `bookings`, `restaurants`, `menu_items`, `orders`, `order_items`) appear in a broad initial schema, while matching Haven/Vorax backend modules are absent. Do not claim these workflows are implemented until handlers and write paths are traced.
2. Corpus's create-booking command writes `corporate_bookings` and reads corporate employees/policies directly. These are appropriate Corpus-owned records, but publication to downstream topics is not shown as transactionally coupled to the database write.
3. `015_payment_integrity.sql` and `016_payment_integrity_base.sql` overlap on `transactions`; validate clean-database execution order and compatibility with existing deployed databases.
4. Migration 003 seeds data within the migrations directory; determine whether seed data is mandatory schema bootstrap or optional development fixture.
5. The Citus schema draft contains tables overlapping the numbered migration schema. Determine whether it is documentation, an alternative deployment schema, or active infrastructure before selecting one as canonical.
6. `audit_log` in a financial migration may be ledger-owned, but global security audit events could need a distinct owner. Do not use one generic table without clear access and retention semantics.
7. Need an explicit migration ledger, checksum/ordering semantics, production startup policy, and tested backup/forward-recovery process before migration changes.

## Next required database work

- Enumerate all `CREATE TABLE`, `ALTER TABLE`, indexes, constraints, triggers, and functions from every SQL file.
- Map each SQL table reference in Go to its owning module and operation (read/write).
- Check whether every write is within the owning domain and whether cross-domain joins are used.
- Validate foreign keys, uniqueness constraints, idempotency keys, and concurrency behavior for rides, reservations, orders, payments, and corporate bookings.
- Run migration tests from an empty database and representative upgrade path when PostgreSQL/Timescale services are available.
- Do not delete or rewrite historical migrations merely to simplify the sequence; use corrective forward migrations when compatibility requires it.
