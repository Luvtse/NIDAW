# Logix Customs Persistence Boundary — 2026-10-24

## Implemented in this checkpoint

- Introduced `CustomsRepository` as an application-owned port. The customs application service no longer imports the shared PostgreSQL adapter or executes SQL itself.
- Added `infrastructure/postgres.CustomsRepository` for prepared declarations, external declaration lookup, submission updates, and status updates.
- Submission updates the declaration and shipment in one database transaction. Customs status updates and the shipment-clearance transition are also transactional.
- Repository writes check affected-row counts so missing or out-of-state records do not silently appear successful.
- Customs declaration preparation rejects nil shipments, missing country/HS-code fields, non-positive package counts, and negative/non-finite declared values before tariff calculation.
- Duty-exemption lookup failures now fail closed rather than silently calculating a possibly incorrect duty. Unknown customs API statuses are rejected instead of being coerced to `pending`.
- Added unit tests for invalid shipment input, exemption lookup failure, duty calculation, and unknown statuses, plus a static architecture regression check.

## Important unresolved risks

- `logix` is not currently mounted from the API composition root, so these services are not proven reachable at runtime.
- No authoritative `customs_declarations` migration was found in `data/migrations/postgres`; the adapter assumes the legacy table and columns used by the original service. The schema must be reconciled before claiming database compatibility.
- Customs authority submission is an external side effect before local persistence. A database failure after external acceptance can leave the remote declaration submitted while local state is stale; idempotency/reconciliation is not implemented here.
- Domain events are still published directly after database commit, not through a transactional outbox. Publish failure can leave committed state without a corresponding event; the caller receives an error, but reliable recovery is not yet implemented.
- No PostgreSQL integration tests or Go package tests could run in this environment because required Go modules are not cached and `GOPROXY=off` prevents fetching them.
- The former blanket 50% reduction for any exemption identifier has been removed. The application now rejects exemption-bearing declarations until an authoritative, auditable calculation policy is provided; see `logix-customs-tariff-policy-contract.md`.

## Validation evidence

Run `python3 scripts/architecture/test-logix-customs-persistence-boundary.py` for static boundary and regression assertions. `gofmt` was run on changed Go files. Go package tests were attempted but blocked before compilation by unavailable modules (`github.com/google/uuid`, `github.com/jackc/pgx/v5`, `go.uber.org/zap`, and `github.com/segmentio/kafka-go`).


## Follow-up hardening — terminal status protection

The PostgreSQL status-update predicate now permits transitions only while the persisted declaration is in `submitted`, `pending`, `under_review`, or `held`. A declaration already `cleared` or `rejected` cannot be overwritten by a later polling response. The adapter also rejects unsupported target status values and non-finite or negative duties/taxes before opening the transaction. These checks are source-level changes; they still require compilation and PostgreSQL integration tests in an environment with dependencies and the authoritative customs schema.


## Transactional event delivery follow-up (2026-10-24)

Customs submission and clearance domain events are now inserted into `logix_event_outbox` inside the same PostgreSQL transactions as the corresponding declaration/shipment state changes. The process-owned dispatcher claims pending rows with `FOR UPDATE SKIP LOCKED`, reclaims stale processing leases, publishes stable event IDs and schema versions, and schedules exponential retries after broker errors. The application service no longer publishes these events directly after commit.

Migration `024_logix_event_outbox.sql` creates the outbox table and pending-work index. The dispatcher starts only when `public.logix_event_outbox` exists. Static checks cover the intended source-level contract; they are not a substitute for compilation or PostgreSQL integration tests.

Remaining risks: delivery is at-least-once and consumers must deduplicate by event ID; downstream schema compatibility is unverified; the external customs API submission and local database commit cannot be made atomic by this outbox and require idempotency/reconciliation. The existing `customs_declarations` and `shipments` schemas still need authoritative migration verification.


## Follow-up hardening — external submission input contract (2026-10-25)

- `SubmitDeclaration` rejects missing declaration/shipment UUIDs before calling the customs authority.
- Empty or whitespace-only external declaration IDs are rejected before local persistence.
- Authority submission errors are wrapped with operation context; local persistence failures are surfaced and explicitly documented as a potential remote/local divergence.
- `PollDeclarationStatus` rejects a zero declaration UUID before repository or authority calls.
- Unit regression tests and static architecture assertions cover these guards.

These checks reduce invalid side effects but do not make external submission atomic or idempotent. A stable authority-side idempotency key or a reconciliation lookup is still required before safe automated retries can be claimed.

## Follow-up hardening — validate authority polling amounts (2026-10-28)

- `PollDeclarationStatus` rejects negative, NaN, or infinite duty/tax amounts from the customs authority before invoking the repository update port. The PostgreSQL adapter retains its own validation as defense in depth.
- Status lookup errors now include operation context while preserving the wrapped cause. Unsupported status values remain rejected before persistence.
- Unit regression tests cover invalid duty/tax values and a valid status update; the architecture script checks the application boundary.

This is source-level hardening only. It does not establish the external authority's currency, rounding, tax-inclusive/exclusive, or schema contract, and does not replace Go compilation or database integration tests.
