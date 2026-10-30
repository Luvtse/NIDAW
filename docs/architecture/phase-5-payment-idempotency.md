# Payment-workflow hardening — Idempotency contract slice

> Historical filename retained for archive/link compatibility. This payment-command change is not acceptance of master-roadmap Phase 5, which is database ownership and migration safety.

## Changes implemented

The payment command previously accepted an empty `IdempotencyKey`. In that case the database's partial unique index did not protect the transaction and the gateway received an empty reference, so retries could create separate charge attempts. The command now requires a non-blank key no longer than 255 characters and trims surrounding whitespace before persisting it or sending it to the provider.

The idempotency claim still uses the database unique index as the concurrency arbiter. When a competing request wins the claim, the loser now compares the committed transaction against the incoming financial intent before replaying it. The replay is accepted only when user, order, order type, amount rounded to two decimals, currency, and normalized payment method match. Reusing a key for a different request returns `ErrIdempotencyConflict`, mapped to HTTP 409 (`IDEMPOTENCY_KEY_CONFLICT`). A missing/invalid key returns HTTP 400 (`IDEMPOTENCY_KEY_REQUIRED`).

The command also copies caller-owned metadata before inserting the idempotency key. This avoids an unintended mutation and potential data race when a caller reuses a request map.

## Tests added

`services/api/internal/modules/payment/application/commands/process_payment_validation_test.go` covers required/bounded keys, identical request replay, mismatched financial intent, and metadata-copy behavior. Existing PostgreSQL integration tests continue to cover concurrent claims and ambiguous provider timeouts when `NIDUS_TEST_DATABASE_URL` is configured.

## Validation status

- `gofmt` applied to changed Go files.
- Targeted Go tests were attempted with `GOPROXY=off`; they could not compile because required Go modules are not cached in this environment. This is an environment/dependency blocker, not a passing test result.
- Live PostgreSQL concurrency tests remain unrun here.

## Remaining payment delivery risk

Payment success events are currently published directly after the transaction status update commits. If the database update succeeds and event publication fails, a retry with the same idempotency key replays the existing transaction and does not guarantee that the missing event will be republished. The repository has outbox patterns in other domains, but the payment command does not yet atomically persist a payment event outbox row with settlement. This is an explicit unresolved reliability gap; do not treat synchronous publish/error reporting as durable delivery.

## Historical migrations

Migrations 015 and 016 both define guarded parts of the `transactions` schema. They have not been rewritten because historical migrations may already be applied in deployed databases. A real PostgreSQL schema diff is required before a forward-only cleanup migration is designed.
