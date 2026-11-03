# API and Event Contracts

## HTTP conventions

The Go API uses Chi routers. Product HTTP routes use the `/api/v1` namespace. Authentication and authorization are applied by the server/router composition; do not infer that an endpoint is public merely because it appears in a route declaration. See [API reference](../reference/api-reference.md) for currently mounted route families.

## Contract rules

- Keep request/response DTOs explicit and stable; do not expose persistence entities as public contracts.
- Validate input at the HTTP boundary and enforce ownership/authorization in the application path.
- Use consistent error responses and avoid leaking secrets or internal database details.
- Version breaking changes; support old and new clients during a defined compatibility window.
- Document authentication, role requirements, pagination, idempotency and error semantics for each externally consumed endpoint.
- WebSocket messages require authenticated identity and resource-level authorization; REST history/state remains the durable source where the implementation uses it.

## Events

Kafka is initialized by the API composition root through `internal/shared/eventbus`. The development setup script creates topic names including `nidus.rides`, `haven.bookings`, `vorax.orders`, `payments` and `driver.locations`. Topic creation is not proof that a fully implemented producer/consumer workflow exists.

For every maintained event contract, document:

- stable event name and schema/version;
- producer and owning domain;
- consumer and purpose;
- aggregate/entity identifier and correlation/idempotency keys;
- timestamp and schema evolution rules;
- retry, dead-letter and replay behavior;
- privacy classification and retention requirements.

## Reliable publication

Where a domain state change and event publication must be atomic, write an outbox record in the same database transaction. Dispatch asynchronously, publish a stable event identifier, and make consumers idempotent. Never rely on a best-effort in-process publish after committing critical business state.

## Contract verification

Verify contracts from the actual mounted router, gateway configuration, client API calls, DTO definitions, SQL constraints and event producer/consumer code. A route or event topic documented without a reachable handler/consumer must be labeled as configured, not implemented.
