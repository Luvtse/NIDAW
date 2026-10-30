# Phase 7 — Ledger outbox PostgreSQL integration gate

## Scope

Adds environment-gated integration tests for the ledger event outbox. The tests use a real `pgxpool` and require `NIDUS_TEST_DATABASE_URL` to point to a **dedicated test database** with `018_ledger_event_outbox.sql` applied. They skip when the environment variable is absent; skipped tests are not evidence of database correctness.

## Coverage added

- Transaction atomicity: insert an outbox event through `EventBusPublisher` inside a PostgreSQL transaction, roll the transaction back, and assert the event row is absent.
- Concurrent dispatch: seed unique pending events and run three dispatcher instances concurrently; assert each event reaches `published` and the recording broker observes one delivery during this run.
- Retry behavior: simulate a broker failure, verify the row returns to `pending` with an incremented attempt count, make the backoff eligible, then verify a later dispatch marks it `published`.

## Run

From `services/api`:

```sh
NIDUS_TEST_DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DEDICATED_TEST_DB?sslmode=disable' \
  go test ./internal/modules/ledger/infrastructure/adapters -run 'TestIntegration_Outbox' -v
```

Apply all required migrations to the dedicated database first. The tests insert and remove rows in `ledger_event_outbox`; do not point them at a production database. Test rows use a unique payload identifier to isolate assertions.

## Validation status

- `gofmt` applied to the added test file.
- Go test execution attempted with `GOPROXY=off`; blocked because required Go modules are not cached and network access is unavailable in this environment.
- No live PostgreSQL or Kafka test was run here. The recording broker validates dispatcher control flow, not Kafka acknowledgement semantics.

## Remaining acceptance gaps

- Run the tests against a dedicated PostgreSQL instance with migration 018 applied.
- Add an actual Kafka/broker integration test in an environment that provides the configured broker.
- Exercise crash-after-broker-acknowledgement explicitly; at-least-once delivery means this case may redeliver and consumers must be idempotent.
- Add metrics for backlog age, pending count, attempts, and last publish error; the current dispatcher logs failures but does not yet expose outbox-specific metrics.
- Verify every provider webhook/top-up/payout code path emits events via the transaction-aware ledger publisher before claiming comprehensive coverage.
