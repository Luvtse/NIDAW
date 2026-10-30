# Phase 0 — Client-to-router coverage delta (2026-10-22)

## Status and method

This is a static source audit of the client call sites, `services/api/cmd/server/main.go`, and the Nidus Chi router. It does not establish live behavior, alternate binaries, external rewrites, or every dynamically constructed request. No client or server API paths were changed in this pass: the canonical contract and compatibility policy must be agreed before coordinated changes.

## Confirmed source-level findings

| ID | Client evidence | Active composition/router evidence | Finding / impact | Required next step |
|---|---|---|---|---|
| CRD-01 | Driver app calls `POST /api/v1/rides/{rideId}/accept`, `/start`, `/complete`, `/cancel`. | Nidus registers lifecycle actions under `/api/v1/nidus/rides/{rideID}/...`; the inspected router has no `/api/v1/rides/{rideID}/...` aliases. | Client/server path mismatch unless an uninspected gateway or alternate entry point rewrites these requests. | Decide canonical route and compatibility window; add router/client contract tests before changing either side. |
| CRD-02 | Consumer and driver clients call `GET /api/v1/nidus/rides/active` and `GET /api/v1/rides/active`. | Nidus registers `GET /api/v1/nidus/rides/{rideID}` but no explicit `/active` handler in the inspected router. `GetRide` parses `rideID` as UUID. | Active-ride lookup is not explicitly mounted; `/active` may be treated as a ride ID and fail UUID parsing. | Define rider vs driver semantics, ownership checks, zero/multiple-active behavior, and DTO before mounting explicit routes. |
| CRD-03 | Consumer safety repository targets `/api/v1/nidus/safety`. | No safety route group was found in `main.go` or the inspected Nidus router. | Safety repository/UI does not have a matching route established by the active composition root. | Trace alternate entry points; otherwise implement real persisted/authorized workflows or expose a truthful unavailable state. Do not add placeholder success handlers. |
| CRD-04 | Driver client references `/api/v1/drivers/profile`, `/status`, `/vehicle`, `/stats`, `/earnings/*`, `/documents*`, `/profile/picture`, and a location update path documented as `/api/v1/drivers/location`. | The inspected `main.go` and Nidus router do not show a mounted `/api/v1/drivers` router. Nidus does mount selected driver capabilities under `/api/v1/nidus/drivers` and `/api/v1/nidus/location`. | Broad driver API family mismatch is indicated; each call needs method-specific tracing because an endpoint name in client code is not enough to establish a registered handler. | Enumerate every method/path and search all router mounts/alternate binaries. Then decide whether to mount an existing handler, update clients, or explicitly mark a capability unsupported. |
| CRD-05 | Consumer analytics repository references `POST /api/v1/analytics/events`. | The inspected composition root has metrics registration, but no matching `/api/v1/analytics/events` registration was found in the searched Go sources. | Client event submission route is not established in the inspected runtime composition. | Trace analytics module registration and alternate entry points; test accepted schema, auth, rate limits, and failure behavior before claiming support. |
| CRD-06 | Admin console source includes `/api/v1/ledger` and `/api/v1/ledger/...` references. | Ledger router mounts under `/api/v1/ledger` only when `EnableInternalLedger` produces non-nil ledger components. | Admin UI availability depends on backend feature/configuration and must not be assumed from the UI route alone. | Verify disabled-state UX, authorization, and exact admin-vs-user permissions in enabled and disabled integration tests. |
| CRD-07 | Consumer pre-selfie client posts to `/api/v1/driver/rides/{rideId}/pre-selfie`; the repository source now sends multipart field `image`. | `main.go` mounts the selfie handler under authenticated `/api/v1` only when `EnablePreSelfie` is enabled; handler expects `image`. | Path and multipart field align statically, but route is feature-conditional and the correction is not validated by Flutter or end-to-end tests. | Add handler/client multipart tests and verify flag-on/off behavior in a running backend. |

## Confirmed route facts in the inspected Nidus router

- `GET /health` and `GET /ready` are registered in the Nidus router; their semantics must be checked independently from proxy-local health responses.
- Ride routes include `POST /api/v1/nidus/rides`, `GET /api/v1/nidus/rides`, `GET /api/v1/nidus/rides/{rideID}`, lifecycle actions, cancellation quote, rating, and feature-gated destination, price-extension, cash-confirmation, and split-fare routes.
- Estimates include `POST /api/v1/nidus/rides/estimate` and `GET /api/v1/nidus/rides/estimates`.
- Selected driver operations are under `/api/v1/nidus/drivers` and location operations under `/api/v1/nidus/location`, not automatically aliases for `/api/v1/drivers/*`.
- Payment-method, promotions, split-fare, WebSocket, and other routes have dependencies or feature gates; client code must handle unavailable states.
- The Go server has global request-ID, real-IP, logging, recovery, timeout, and metrics middleware. These global middleware do not replace resource ownership, role, or tenant authorization.

## Validation attempted

- Static grep/inspection confirmed the client path literals and router registrations cited above.
- `go test ./internal/modules/nidus/interfaces/http/... ./cmd/server` was attempted from `services/api`, but dependency downloads did not complete before the command timeout. This is **not a test pass**; test status remains blocked/unverified in this environment.
- No Docker, Kong, PostgreSQL, Flutter, or browser-level integration request was run in this pass.

## Required Phase 0 exit work

1. Generate a complete method/path registry from the actual Chi router, including conditional mounts and middleware, rather than relying on string grep.
2. Build a client method/path inventory for consumer, driver, and admin applications, including dynamically composed paths and request/response/error expectations.
3. Resolve the confirmed path gaps above through reviewed API decisions and coordinated client/server tests; do not make speculative aliases or placeholder implementations.
4. Add negative tests for role, ride ownership, driver ownership, admin privileges, and tenant/resource boundaries.
5. Validate effective Kong forwarding, Compose/Kubernetes service discovery, and route reachability against a running backend.
6. Re-run clean-checkout Go and Flutter baselines and database migration validation in an environment with dependencies and required services.
7. Keep Phase 0 open until its acceptance gate is evidenced; these static findings do not authorize Phase 1 acceptance.
