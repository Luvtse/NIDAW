# Phase 0 — Client endpoint literal inventory (2026-10-22)

## Status and method

This inventory was generated from source literals under `apps/consumer_app/lib`, `apps/driver_app/lib`, and `apps/admin_console/src`. It is a discovery artifact, not a complete API contract or proof of runtime reachability. The CSV records source file, line, guessed HTTP method (where inferable), path literal, and evidence line. A method marked `UNRESOLVED` must be manually resolved; paths assembled from constants/interpolation and endpoints represented as relative paths may not be captured.

- Client-side endpoint-like literal references: **71** (references, not necessarily unique operations).
- Consumer app references: **46**; unique path literals: **34**.
- Driver app references: **24**; unique path literals: **20**.
- Admin console references: **1**; unique path literals: **1**.
- Method extraction counts: DELETE=1, GET=19, PATCH=4, POST=22, UNRESOLVED=25.

Full line-level inventory: `phase-0-client-endpoint-literal-inventory-2026-10-22.csv`.

## High-confidence contract mismatches from static source

1. **Driver ride lifecycle prefix:** driver app calls `POST /api/v1/rides/{rideId}/accept`, `/start`, `/complete`, and `/cancel`; the inspected Nidus router registers those lifecycle handlers under `/api/v1/nidus/rides/{rideID}/...`. No compatibility alias or gateway rewrite for the legacy path was established in the inspected source.
2. **Active ride:** consumer and driver clients call `/api/v1/nidus/rides/active` and `/api/v1/rides/active`, respectively. The inspected router has no literal active-ride route. The generic `GET /api/v1/nidus/rides/{rideID}` route may capture `active`, then UUID parsing fails; this is not equivalent to active-ride retrieval.
3. **Driver profile/status/stats/earnings/documents/vehicle:** client code calls `/api/v1/drivers/...`; inspected Nidus routes expose `/api/v1/nidus/drivers/nearby`, `/pending-rides`, and `/{driverID}` only. No corresponding `/api/v1/drivers/profile`, `/status`, `/stats`, `/earnings/*`, `/documents*`, or `/vehicle` handler was found in the scanned active API source.
4. **Driver location:** client code documents `/api/v1/drivers/location`, while the Nidus router exposes `POST /api/v1/nidus/location/update` and `GET /api/v1/nidus/location/driver/{driverID}`. The driver home repository currently sends location updates over WebSocket instead of invoking the documented REST path; reconcile which contract is intended.
5. **Safety:** consumer repository uses `/api/v1/nidus/safety`; no corresponding route group was found in the inspected active composition. The repository's fallback behavior must be reviewed to ensure safety actions never report success when the backend is unavailable.
6. **Analytics:** consumer references `POST /api/v1/analytics/events`; no matching route registration was established in the inspected composition root.
7. **Pre-selfie upload:** server mounts `POST /api/v1/driver/rides/{rideId}/pre-selfie` only when `FEATURE_PRE_SELFIE` is enabled. A stale client comment still said multipart field `selfie` although the server and implementation use `image`; the comment was corrected in this pass. Add a regression test to lock the field name.
8. **Admin console:** client base is `/api/v1/ledger`, so actual endpoints are formed by combining this base with relative path constants. Literal-only scanning of full `/api/v1/...` strings under admin is insufficient to determine every effective endpoint; inspect each `req()` call and relative suffix before treating the admin inventory as complete.

## Security and acceptance implications

- A route existing in a module is not evidence it is mounted, and a mounted route is not evidence the client method/path matches.
- Route-level middleware and handler-level ownership checks must be reviewed separately, particularly for rider/driver ride access, location disclosure, safety actions, ledger mutations, and pre-selfie redemption.
- Feature-gated routes need explicit enabled/disabled tests and truthful client unavailable states.
- Do not add broad aliases or placeholder endpoints solely to silence mismatches. Agree the canonical API contract, then make coordinated server/client changes with compatibility and authorization tests.

## Next required actions

1. Resolve admin relative paths and all client method inference marked `UNRESOLVED`.
2. Produce a mounted router registry including route groups, feature conditions, auth middleware, and role/resource authorization.
3. Reconcile each effective client operation with the registry and `services/api/api/openapi.yaml`; add missing OpenAPI paths only after request/response/error schemas are verified from handlers.
4. Prioritize driver lifecycle, active ride, driver profile/status/earnings/documents/location, safety, and analytics.
5. Run Flutter/TypeScript and Go contract tests in an environment with dependencies available, then verify gateway URI forwarding against a running stack.

## Phase 0 status

Phase 0 remains open. This inventory improves static traceability but does not provide a complete client/server contract matrix, live routing evidence, clean-checkout build baselines, database migration execution, or route-level authorization test evidence.
