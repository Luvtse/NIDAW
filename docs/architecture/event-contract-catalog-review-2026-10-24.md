# Cross-product event contract catalogue review — 2026-10-24

## Scope

Added `packages/event-contracts/catalog.json` as a first, deliberately partial catalogue of observed event contracts. It records event type, schema version, producer/source paths, topic, required payload fields, known consumers, and the known verification gap. `scripts/architecture/test-event-contract-catalog.py` checks the catalogue structure, source-file existence, and presence of the high-risk Corpus/Logix handoff contracts.

## Evidence-backed entries

- Corpus booking creation emits `corpus.booking.created` on `corpus.bookings` with schema version 1.
- Corpus approval emits `corpus.booking.approved` to a service-specific topic (`nidus.rides`, `haven.bookings`, `vorax.orders`, or `logix.shipments`). Rejection emits `corpus.booking.rejected` on `corpus.bookings`.
- Logix customs clearance emits `logix.customs.cleared` on `logix.customs` with schema version 1.
- Logix load matching currently publishes `logix.load.matched` directly to `logix.loads` without an explicit schema version or transactional outbox. This remains a migration gap, not a compliant v1 event.
- Notifications and Telephony handle `ride.matched` and `ride.completed`, but producer-by-producer payload/topic compatibility remains unverified.

## Compatibility rules recorded

1. New event contracts must state an explicit schema version starting at 1.
2. Version 0 or absent version is legacy and must not be treated as conforming to a v1 contract.
3. Do not silently change required fields; use a compatible evolution or a new major contract/event type.
4. Outbox/reliable-subscriber paths provide at-least-once delivery; consumers must be idempotent.

## Important limitations

- This is not yet a complete catalogue of all events, all five products, HTTP APIs, webhooks, or provider callbacks.
- The structural script verifies catalogue shape and source-file existence; it does not parse Go ASTs, validate runtime payloads, or prove topic/payload compatibility.
- No active consumer for the listed Corpus and Logix handoff events was identified in the inspected module source. Runtime composition for Corpus/Logix remains a known gap.
- `logix.load.matched` remains a legacy direct-publish path. It should be moved behind a versioned contract and durable outbox only after its persistence transaction and consumer needs are traced.
- This checkpoint advances Phase 6 evidence but does not accept Phase 6 or authorize Phase 7 acceptance.

## Next evidence required

1. Trace every producer callsite and its transaction boundary.
2. Identify and mount supported consumers for Corpus -> Nidus/Haven/Vorax/Logix handoffs.
3. Add schema-level provider/consumer tests for v1 payloads and legacy compatibility.
4. Validate all contract paths with Go tests and PostgreSQL/Kafka integration tests in a dependency-enabled environment.

## Follow-up — versioned Logix load-match outbox path

- Replaced `LoadMatcher`'s ignored direct Kafka publish with the `LoadMatchEventWriter` application port. Failure to persist publication intent now fails the match operation rather than silently losing the event.
- Added `LoadMatchEventRepository`, which validates identifiers and numeric values and inserts `logix.load.matched` schema version 1 into `logix_event_outbox`.
- Updated the catalogue to version 1 and the exact source paths; the catalogue explicitly retains the fact that no active downstream consumer was identified.
- Limitation: this workflow currently does not persist a load status transition, so the outbox row is durable but is not atomic with a load-state mutation. `NewLoadMatcher` also has no active runtime call site in the inspected repository. Runtime mounting, authoritative schema validation, and PostgreSQL/Kafka integration tests remain open.
- Static regression coverage: `scripts/architecture/test-logix-load-matched-outbox.py`.
