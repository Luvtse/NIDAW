# Phase 0 — Route security and active-ride error mapping delta (2026-10-22)

## Status

This continuation makes two narrow source changes supported by direct inspection. It does not close Phase 0 or resolve the client/server active-ride path contract.

## Change 1 — WebSocket middleware comment corrected

`services/api/internal/modules/nidus/interfaces/http/router.go` registers `GET /ws` inside the protected `r.Group` that applies `AuthRequired` and `ExtractUserToContext`. The handler `HandleWebSocket` also extracts and validates a WebSocket access token before attempting the upgrade.

The prior nearby comment said the route was outside `AuthRequired`, which contradicted the code structure. The comment now describes the actual composition and explicitly retains both checks pending authenticated/unauthenticated handshake regression tests. Runtime behavior was not changed.

## Change 2 — Active-ride database failures no longer masquerade as domain absence

`RideHandler.GetActiveRide` already existed but was not mounted in the inspected router. It resolves the driver's profile, then queries the driver's current non-terminal ride. Previously, every error from both database queries was mapped to a domain response (`NOT_A_DRIVER` or `ACTIVE_RIDE_NOT_FOUND`), including connection/query failures.

The handler now distinguishes `pgx.ErrNoRows` from other query errors:
- no driver row -> `403 NOT_A_DRIVER`
- driver lookup database failure -> `500 INTERNAL_ERROR`
- no active ride row -> `404 ACTIVE_RIDE_NOT_FOUND`
- active-ride lookup database failure -> `500 INTERNAL_ERROR`

This is a narrow error-semantics correction. It does not mount the handler or choose the public client route. A database-backed test remains required.

## Active-ride contract remains unresolved

Source inspection still shows:
- Consumer app calls `GET /api/v1/nidus/rides/active`.
- Driver app calls `GET /api/v1/rides/active`.
- Handler comment describes `GET /api/v1/nidus/drivers/active-ride`.
- No matching active-ride registration appears in `services/api/internal/modules/nidus/interfaces/http/router.go`.

Do not add aliases or mount the handler until the canonical rider-versus-driver semantics and response DTO are agreed. A driver's assigned ride and a rider's active ride may require different ownership queries and should not be collapsed into one implementation without evidence.

## Validation performed

- Ran `gofmt` on both modified Go files.
- `GOPROXY=off go test ./internal/modules/nidus/interfaces/http/handlers ./internal/modules/nidus/interfaces/http` was attempted. It failed before compilation because required Go modules are not present in the local cache and network module lookup was disabled. No tests passed in this attempt.
- No live WebSocket handshake, PostgreSQL failure simulation, or HTTP contract test was run.
- This report is source evidence, not runtime verification.

## Next actions

1. Obtain a dependency-enabled Go environment and add tests for the two active-ride query error branches.
2. Add WebSocket handshake tests for missing, invalid, and valid access tokens through the actual mounted router.
3. Agree separate canonical active-ride contracts for consumer and driver clients; implement handler(s), mount(s), DTO(s), OpenAPI entries, and client updates together.
4. Re-run router/client/OpenAPI/gateway comparison and record the results.

## Acceptance

Phase 0 remains open. Runtime routing, authorization, migrations, deployment reachability, and full client contract alignment remain unverified.
