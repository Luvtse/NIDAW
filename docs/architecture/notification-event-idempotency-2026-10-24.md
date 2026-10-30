# Notifications event idempotency correction — 2026-10-24

## Problem

The notification consumer derived dedupe keys from `(event type, ride ID)` for all ride events. This is too broad for event types that may occur more than once during one ride. In particular, `driver.arriving` can be emitted for multiple approach-radius tiers, and `ride.destination_changed` can occur multiple times as the rider changes destination. The earlier comment that outbox `event_id` equals the ride ID was also inaccurate: Corpus and Logix outbox dispatchers assign a stable UUID to each outbox row.

## Change

1. Use `event:<event_id>` whenever the event envelope carries a stable ID.
2. For older events without an ID, retain the `(type, ride ID)` fallback for one-per-lifecycle event types.
3. For legacy `driver.arriving`, include `approach_tier`; when no tier is available, do not deduplicate by ride alone.
4. For legacy `ride.destination_changed`, include the new destination coordinates/address; when no destination identity is available, leave the event unkeyed.
5. Keep payment and promotion legacy fallback keys as before.

## Verification and limits

- `scripts/architecture/test-notification-event-idempotency.py`: 9/9 assertions passed.
- `scripts/architecture/test-reliable-product-subscribers.py`: 11/11 assertions passed.
- `scripts/architecture/test-event-consumer-commit-contract.py`: 13/13 assertions passed.
- `scripts/architecture/check-go-product-boundaries.py`: passed (direct imports only).
- Go package tests and durable PostgreSQL idempotency integration tests still require a dependency-enabled test environment.

The fallback destination key is not a substitute for a producer event ID: if two distinct legacy destination changes have identical destination fields, they intentionally collapse to one notification. Producers should emit stable unique event IDs for all business transitions.
