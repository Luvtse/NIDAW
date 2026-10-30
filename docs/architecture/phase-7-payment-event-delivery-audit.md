# Phase 7 — Payment event delivery: active-path audit

> This is a partial Phase 7 implementation audit. It does not indicate Phase 7 acceptance; master-roadmap Phases 3–6 remain prerequisite gates.

## Decision

Do not implement a transactional outbox solely inside `internal/modules/payment/application/commands/ProcessPaymentHandler`. The first implementation slice now targets the active ledger `EventPublisher` contract. The current composition root (`cmd/server/main.go`) does not mount that handler. The active payment API path is registered through `ledgeradapters.NewWebhookHandler` under `/api/v1/payments`, with top-up and payout jobs started alongside it. The `modules/payment` command has its own tests and HTTP handler, but that is not evidence of production runtime reachability.

## Evidence in repository

- `services/api/cmd/server/main.go` mounts `ledgerhttp.NewRouter` at `/api/v1/ledger` and registers `ledgeradapters.NewWebhookHandler` beneath `/api/v1/payments` when `ledgerComps` and `ledgerResolver` are available.
- The same composition branch starts `NewTopupJob` and `NewPayoutJob`.
- No `NewProcessPaymentHandler` call was found in the composition root. Its HTTP handler is therefore not wired by the main server path currently inspected.
- `ledger/infrastructure/adapters/eventbus.go` implements `EventBusPublisher.Publish` by directly calling the event bus. The `services.DBTx` argument is deliberately unused; comments already acknowledge that an outbox is future work.
- `ledger/application/commands/ports.go` describes `EventPublisher` as a transactional-outbox port, but the concrete adapter does not currently provide that guarantee. This is a contract/implementation mismatch that needs resolution.
- Other lifecycle areas already have outbox patterns (`ride_completed_events` in migration 005 and `ride_matched_events` in migration 014); they are useful local examples but do not make payment event publication durable.

## Implementation status (partial)

- Added `data/migrations/postgres/018_ledger_event_outbox.sql` with a durable event table and pending-work index.
- Changed `ledgeradapters.EventBusPublisher` to insert the event into the supplied `services.DBTx`, instead of publishing directly to Kafka. A missing transaction now returns an error rather than silently bypassing durability.
- Added `OutboxDispatcher` with row claims, `SKIP LOCKED`, a one-minute processing lease, bounded exponential retry delay, and published-state recording after broker acknowledgement. Delivery is at-least-once, not exactly-once.
- Wired the dispatcher into the ledger-enabled server lifecycle and added publisher adapter unit tests.
- This is an initial implementation slice, not proof that every top-up, payout, webhook, and escrow transition emits through this port. Those call paths still require a transaction/event trace and integration tests.

## Required implementation sequence

1. Map every active money-moving operation (provider webhook settlement, top-up confirmation, payout completion, ride settlement, escrow release) to its DB transaction and emitted event.
2. Add a forward-only migration for a generic or narrowly scoped ledger outbox with stable event ID, aggregate/transaction ID, event type, JSON payload, creation time, attempt count/last error, and nullable published timestamp. Add indexes for unpublished rows and deterministic claiming.
3. Write outbox rows inside the same database transaction as the corresponding money/state change. The transaction boundary must be explicit in the UoW/repository interfaces; merely passing a `DBTx` to a publisher and ignoring it is not sufficient.
4. Add a dispatcher that safely claims batches, publishes outside the DB transaction, and marks success only after broker acknowledgement. Use leases or `FOR UPDATE SKIP LOCKED` to coordinate replicas; expect at-least-once delivery and require idempotent consumers.
5. Wire dispatcher lifecycle and shutdown into `cmd/server/main.go`; expose metrics/logging for backlog age, retries, and publish failures.
6. Add repository/dispatcher tests for rollback atomicity, crash-after-publish duplicate delivery, concurrent workers, retry/backoff, poison events, and graceful shutdown. Run integration tests against real PostgreSQL and the configured broker before claiming production readiness.
7. Separately decide whether the legacy `modules/payment` command is to be integrated or retired. Do not silently wire it as part of an outbox patch without resolving routing, ownership, and API contract duplication.

## Acceptance criteria

- No money/state transition that promises a downstream event can commit without the matching durable outbox record.
- A broker outage leaves events pending and retryable without rolling back already committed money movement.
- A dispatcher crash after broker acknowledgement can cause duplicate delivery, but cannot lose the event; consumers are idempotent.
- Tests demonstrate transaction atomicity and multi-worker safety against PostgreSQL.
- Runtime wiring and the API route ownership are documented and verified from the composition root.

## Validation limits

Source edits and formatting were performed. Go test execution, migration application, broker delivery, PostgreSQL atomicity, multi-worker claiming, and graceful-shutdown behavior still require validation in an environment with cached Go dependencies and live PostgreSQL/Kafka. Do not claim production readiness until those checks pass.

## Event coverage discovered during implementation

The ledger command layer invokes the event port from ride settlement, top-up requests/verification, withdrawal/payout transitions, disputes, and escrow release. These call sites pass the command transaction to the port, so the new publisher persists their events atomically when those paths use the configured `EventBusPublisher`. Provider adapters may also perform state changes through separate paths; they must be checked independently rather than assumed covered by this list.
