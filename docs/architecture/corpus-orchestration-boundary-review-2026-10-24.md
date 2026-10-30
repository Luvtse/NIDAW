# Corpus orchestration boundary review — 2026-10-24

## Scope

Reviewed `services/api/internal/modules/corpus/application/commands/create_booking.go` against the roadmap requirements for Phase 3 (domain boundaries), Phase 4.5 (Corpus workflow integrity), Phase 6.3 (cross-product contracts), and Phase 7.4 (Corpus orchestration).

## Evidence and findings

1. `CreateCorporateBookingHandler` directly queries `corporate_employees` and `travel_policies`, inserts `corporate_bookings`, and publishes events. The use case therefore mixes application orchestration, persistence, policy evaluation, and messaging instead of depending on explicit ports.
2. The booking row is inserted before `h.bus.Publish`. The publish error is ignored, so the API can report success even when `corpus.booking.created` was not published. The database mutation and event publication are not atomic.
3. `forwardToService` publishes a generic `corpus.booking.approved` event to a product topic. The current code does not show a versioned product-specific command/contract, a correlation/idempotency key, or a persisted orchestration state for retries and partial failures.
4. Approver lookup errors are ignored. When an amount rule requires approval but no approver is found, the booking can remain `pending_approval` with a nil approver and no explicit escalation/error outcome.
5. `bookingData` is an untyped map and policy evaluation silently treats missing/wrongly typed values as zero values. This can turn malformed input into an apparently policy-compliant result; request validation and typed service-specific command contracts are required before the policy result can be trusted.
6. `EvaluateBooking` accepts `employeeID` but does not use it. The selected policy is scoped by corporate ID, which is appropriate for policy ownership, but the unused parameter obscures the contract.

## Required follow-up

- Define typed Corpus commands/results and policy evaluation inputs per service type.
- Split policy evaluation from persistence and orchestration.
- Introduce repository and product-contract ports; Corpus must not mutate product-owned state directly.
- Persist booking state and an outbox record in the same PostgreSQL transaction, then publish with retry and idempotency semantics. Do not reuse Ledger's outbox table without an explicit ownership/design decision.
- Model approval as explicit states, including no-approver/escalation behavior and authorized approver transitions.
- Add unit tests for malformed policy input, approval thresholds, missing approvers, retries, duplicate events, and partial downstream failures; add integration tests for transaction/outbox behavior.

## Status

This is a blocker-oriented review, not an implementation claim. Corpus's current command is not ready to be treated as reliable cross-product orchestration. The refactor should be performed as a dedicated, behavior-preserving slice after agreeing the product contracts and event/outbox ownership.

## Follow-up implementation slice — policy validation (2026-10-24)

Implemented in this checkpoint:

- Extracted deterministic service-specific policy evaluation into `domain/policy`, with no database or event-bus dependency.
- Required the service-specific fields used by ride, hotel, food, and freight policy checks. Missing or wrongly typed values now return validation errors rather than silently becoming zero values.
- Added validation for the shared `amount` used by approval and employee spending-limit decisions (required, finite, and non-negative).
- Reject unsupported service types rather than returning an empty violation list.
- Changed approval routing to fail closed if a required approver cannot be resolved, and made selection deterministic among eligible approvers.
- Added focused unit tests for missing fields, policy violations, unknown service types, invalid amounts, and RFC3339 timestamps.

Still unresolved and deliberately not represented as complete:

- `CreateCorporateBookingHandler` still performs SQL directly and owns orchestration; repository/product-contract ports are not yet introduced.
- The booking write and event publication are still not atomic. Publish errors and downstream handoff errors remain unhandled; a Corpus-owned transactional outbox and dispatcher are required before reliability can be claimed.
- The command still accepts `map[string]interface{}` at its boundary. This slice validates required fields, but does not replace it with distinct compile-time typed commands for each product contract.
- Approval states, authorization, escalation, retry/idempotency, and PostgreSQL integration behavior remain unverified.
- Unit tests could not be executed in this environment because `github.com/google/uuid` is unavailable locally and dependency retrieval timed out. Source formatting completed, but compilation and test success are not claimed.

## Follow-up implementation — application port and transactional outbox (2026-10-24)

Implemented in this checkpoint:

- Added `application/ports.BookingRepository` for employee lookup, active policy lookup, approver resolution, and booking persistence.
- Refactored `CreateCorporateBookingHandler` and `PolicyEngine` to depend on the application port rather than `database.Postgres` or `eventbus.EventBus`; SQL has been removed from the command handler.
- Added the PostgreSQL adapter under `infrastructure/postgres`. `CreateBookingWithEvents` inserts the booking and all corresponding outbox records in the same database transaction, so a failed outbox insert rolls the booking back.
- Added `020_corpus_event_outbox.sql` and an at-least-once dispatcher with a processing lease, retry backoff, and error recording.
- The command now returns persistence failures instead of reporting success when the write transaction fails. Automatic downstream service events are persisted with the booking-created event, rather than published inline.
- Added fake-repository tests for successful orchestration, fail-closed approval routing, and persistence error propagation.

Important remaining deployment/runtime gaps:

- The Corpus handler has not been wired to an HTTP route or server composition root because this repository currently has no Corpus booking route to extend safely.
- The dispatcher is implemented but is not started in `cmd/server/main.go`; it must only be enabled after migration `020_corpus_event_outbox.sql` is applied and a Corpus booking route is wired.
- The repository's checked-in PostgreSQL migration set does not define `corporate_bookings`, `corporate_employees`, or `travel_policies`. This change assumes those tables are supplied by an existing deployment schema; that assumption must be verified before production rollout.
- At-least-once delivery means downstream consumers need idempotency. This implementation does not itself establish consumer-side idempotency or a complete approval/escalation state machine.
- Go package tests could not run in the current environment because required modules were not present in the local Go module cache and network retrieval was unavailable. Compilation and PostgreSQL integration remain unverified.
- Corrected the shared Kafka publisher to honor the topic passed to `EventBus.Publish`; previously the Kafka writer had a fixed `nidaw.events` topic and ignored the per-call topic, which would have broken module-specific outbox routing.

## Follow-up checkpoint — schema ownership and worker startup (2026-10-24)

The follow-up implementation adds `data/migrations/postgres/021_corpus_core_schema.sql` for the Corpus-owned `corporate_accounts`, `corporate_employees`, `travel_policies`, and `corporate_bookings` tables, plus an explicitly destructive down migration. The schema aligns with the columns used by the current repository adapter and adds foreign keys, basic domain constraints, and query indexes. This is a proposed forward migration; it has not been applied against a live or representative PostgreSQL database and must be reviewed against any deployed corporate data before rollout.

The server composition root now conditionally starts the outbox dispatcher only when `to_regclass('public.corpus_event_outbox')` confirms migration 020's table exists. If the table is absent or the readiness query fails, the server logs a warning and leaves the dispatcher stopped rather than repeatedly querying a missing table. This is not a full migration-readiness gate for the entire application.

A static regression check was added at `scripts/architecture/test-corpus-schema-and-outbox-wiring.py`. It confirms the migration contains the tables and repository columns used by the adapter, that booking and outbox writes share `WithTx`, and that the dispatcher is wired behind a schema-presence check. The static check passed. Go tests remain unverified because this environment cannot retrieve `github.com/google/uuid` and other Go dependencies with `GOPROXY=off`.

Still open: the Corpus create-booking handler is not mounted on an HTTP route. Before exposing it, define the API contract and ensure the authenticated user's `user_id` maps to the employee record inside the specified corporate account; the request must not be trusted to nominate an arbitrary employee UUID. The migration also needs review against production schema/data and PostgreSQL integration tests. Downstream event consumers still require idempotency because the dispatcher guarantees at-least-once, not exactly-once, delivery.


## Follow-up checkpoint — event contract versioning (2026-10-24)

- Added migration `022_corpus_outbox_contract_version.sql`; existing outbox records default to schema version 1, and new rows require a positive version.
- Corpus application events now declare schema version 1. The repository persists that version alongside the outbox record.
- The dispatcher propagates the outbox row UUID as `event_id` and the schema version into the shared event envelope. Optional JSON fields preserve compatibility for existing event producers that do not yet populate these fields.
- Added `scripts/architecture/test-corpus-event-contract-versioning.py` to check the migration, persistence, and propagation path.

The static versioning assertions passed. This is a versioning foundation, not a completed typed-contract migration: `booking_data` remains generic, existing consumers have not been verified to honor versions or deduplicate event IDs, and PostgreSQL/Go integration tests remain blocked by the unavailable Go dependency cache.

## Approval lifecycle implementation checkpoint (2026-10-24)

The API now exposes authenticated `POST /api/v1/corpus/bookings/{bookingID}/approve` and `/reject` operations. The decision command accepts the authenticated user ID from request context, not a client-provided approver ID. The PostgreSQL adapter locks the target booking, verifies that the authenticated user maps to the currently assigned active approver membership and active corporate account, rejects non-pending bookings, transitions the state, and appends the decision event to the Corpus outbox in the same transaction. Approved bookings emit a product-topic `corpus.booking.approved` event; rejected bookings emit `corpus.booking.rejected` on `corpus.bookings`. Migration 023 adds decision timestamp and notes fields.

Static regression assertions and formatting pass. Go compilation/unit tests and PostgreSQL integration tests remain unverified because required Go modules are unavailable in the current offline environment. The route is registered but should not be considered production-verified until authentication middleware, migration execution, concurrent decision behavior, and downstream event consumers are exercised in integration tests.
