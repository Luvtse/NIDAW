# Phase 0 — Active-ride endpoint contract trace

## Scope and method

Static trace of consumer/driver repository calls, the active Nidus Chi router, and the existing handler. No live HTTP request or database query was run for this report.

## Findings

### Consumer lookup

- Client call: `GET /api/v1/nidus/rides/active` in `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart`.
- Router: the protected `/api/v1/nidus/rides` group registers `GET /` and `GET /{rideID}`, but no literal `GET /active`.
- Detail handler: `RideHandler.GetRide` parses `{rideID}` as a UUID and returns `400 INVALID_ID` when it receives `active`.
- Existing query infrastructure (`ListRidesQuery`) is user-scoped but its status filter accepts one exact status; it does not itself implement “any non-terminal active status.”

Conclusion: the consumer active-ride call has no explicit matching route in the inspected router. Based on route registration and UUID parsing, it is expected to hit the detail handler and fail with `INVALID_ID`, unless an external rewrite or different running binary changes the request path.

### Driver lookup

- Client call: `GET /api/v1/rides/active` in `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart`.
- The active Nidus router does not register this legacy path.
- A handler already exists: `RideHandler.GetActiveRide`, documented for `/api/v1/nidus/drivers/active-ride`. It resolves the authenticated user to a driver profile and selects rides assigned to that driver in `matched`, `driver_en_route`, or `in_progress` status.
- The inspected router does not register `/api/v1/nidus/drivers/active-ride`, so the existing handler is currently not exposed there.
- The driver query treats any database query error as `ACTIVE_RIDE_NOT_FOUND` (404), not just “no rows.” This masks database failures as an empty active-ride result and should be corrected while wiring the handler.

Conclusion: driver lookup has both a path mismatch and an existing but unmounted driver-specific handler. The handler’s query and error mapping should be tested before exposure.

## Safe implementation direction

1. Expose the driver handler at the documented canonical path `/api/v1/nidus/drivers/active-ride`, and update the driver client to call it. If deployed clients require the legacy route, retain a deliberate temporary alias rather than assuming a gateway rewrite exists.
2. Add a separate rider-scoped active-ride handler for `/api/v1/nidus/rides/active`. It must query by authenticated rider/user identity, include only the explicitly agreed active statuses (at minimum `requested`, `matched`, `driver_en_route`, `in_progress` if `requested` is considered active in the domain), return the same ride DTO shape as ride detail, and return 404 only for no matching row.
3. Register the literal `/active` route before `/{rideID}` for readability and to avoid accidental catch-all capture. Confirm Chi routing behavior with a router-level test.
4. Define behavior for multiple active rides. Prefer enforcing the domain/database invariant and surfacing an integrity error over silently picking an arbitrary ride.
5. Add handler/router tests for rider and driver identity isolation, no active ride, one active ride, multiple active rows, database error, malformed/unauthenticated identity, and exact response DTO compatibility.
6. Only after tests pass, update the API contract inventory and mark this specific finding resolved. No live gateway or deployed environment has been verified by this static trace.

## Status

Phase 0 remains open. This trace confirms the driver handler exists but is not mounted in the inspected Nidus router; it does not claim that any live deployment is currently affected.
