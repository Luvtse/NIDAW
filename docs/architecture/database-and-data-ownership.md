# Database and Data Ownership

## Persistence layout

- PostgreSQL migration source: `data/migrations/postgres/`.
- TimescaleDB migration source: `data/migrations/timescale/`.
- Seed data: `data/seeds/` and `scripts/seed/`.
- Shared PostgreSQL adapter: `services/api/internal/shared/database/`.
- Product-specific repositories/adapters: each product's `infrastructure/` directory.
- Historical schema sketches also exist under `database/`; verify their compatibility with ordered migrations before treating them as the deployed schema.

## Ownership principles

| Owner | Data responsibility |
|---|---|
| Nidus | Ride lifecycle, dispatch-related state, fare snapshots/amendments, stops, driver onboarding/document records where implemented |
| Haven | Hotel catalog, inventory and accommodation booking records |
| Vorax | Restaurant/menu reads and food order lifecycle records |
| Logix | Shipment/carrier/customs records and Logix event outbox records where migrations/repositories exist |
| Corpus | Corporate account, booking requests, approval decisions and Corpus outbox records |
| Payments | Payment-provider transactions and payment-method state |
| Ledger | Financial entries, escrow/settlement and reconciliation records |
| Shared platform | Identity, sessions, notifications and technical metadata according to their owning module |

This is a domain-level ownership guide. The exact table-to-owner map must be maintained against SQL migrations and repository queries; a migration filename alone does not establish exclusive runtime ownership.

## Migration safety

- Apply migrations in the repository's intended numeric/order sequence using the migration scripts under `scripts/migrations/`.
- Review every `*_down.sql`/`*_down` migration and rollback behavior before production use.
- Do not manually apply a subset of migrations to a live database without checking dependencies and migration tracking.
- Back up the database and verify restore before destructive schema changes.
- Prefer additive, backward-compatible schema changes; deploy compatible readers/writers before removing old columns or constraints.
- Preserve idempotency and uniqueness constraints for payment, booking, ride and event workflows.

## Integrity requirements

- A product must not read/write another product's private tables to orchestrate a workflow.
- Financial posting must be traceable to an originating business operation and have an auditable reversal/correction path.
- Outbox records must be committed in the same transaction as the business state change they represent.
- Consumers must tolerate duplicate delivery and record processing outcomes.
- Referential integrity and transaction boundaries must be reviewed before splitting data ownership.

## Source of truth

The ordered SQL migrations and repository queries are the implementation evidence. `database/` schema snapshots and older inventory documents are secondary references and must not override current migrations.
