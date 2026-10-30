# Phase 0 — API contract and client inventory coverage (2026-10-22)

## Status

Static documentation and source audit only. This document extends `endpoint-client-contract-trace.md` and `phase-0-client-router-coverage-delta-2026-10-22.md`; it does not replace a complete method-by-method client/server contract matrix or runtime verification. No endpoint implementations or client paths were changed in this pass.

## Confirmed contract-spec coverage gap

`services/api/api/openapi.yaml` currently declares exactly four paths:

| Method | Path |
|---|---|
| POST | `/api/v1/auth/register` |
| POST | `/api/v1/auth/login` |
| POST | `/api/v1/nidus/rides` |
| POST | `/api/v1/nidus/rides/estimate` |

The OpenAPI document declares `openapi: 3.0.3` and version `1.0.0`. In the inspected source, this four-path specification does not describe the broader active REST surface or the client-referenced capabilities. Treat it as a partial specification until completeness is explicitly established; do not use it as the full API inventory or generate clients from it as if it were complete.

## Additional mounted route families confirmed in source

| Route family | Evidence | Mounting / security qualification |
|---|---|---|
| Authentication | `internal/modules/auth/interfaces/http/router.go` | Mounted at `/`; public login/register/refresh; authenticated `/me`, logout, profile update, and password change. Router also registers `/health`. |
| Legal documents and consent | `internal/modules/legal/interfaces/http/router.go` | Public legal-document read; consent endpoints authenticated; document mutation and audit-export routes require the `admin` role. |
| Nidus rides, drivers, location, WebSocket | `internal/modules/nidus/interfaces/http/router.go` | Ride and driver routes are under authenticated groups except public fare estimates and tokenized split invite acceptance. Cash, destination change, price extension, split-fare, payment-method, promotion, and WebSocket surfaces are conditional on dependencies or flags. |
| Notifications | `cmd/server/main.go` and `internal/modules/notifications/interfaces/http/handlers.go` | `/api/v1/notifications` is mounted only in the notifications-enabled composition and has auth + user-context middleware. |
| Chat | `cmd/server/main.go` and `internal/modules/chat/interfaces/http/handlers.go` | `/api/v1/chat` is mounted only when chat is enabled and has auth + user-context middleware. |
| Telephony | `cmd/server/main.go` and `internal/modules/telephony/interfaces/http/handlers.go` | `/api/v1/telephony` is feature-gated; the mounted route is authenticated. |
| Selfie verification | `cmd/server/main.go` and `internal/modules/selfie/interfaces/http/handlers.go` | Mounted under authenticated `/api/v1` only when pre-selfie is enabled; public signed redemption semantics need separate verification. |
| Ledger | `cmd/server/main.go` and `internal/modules/ledger/interfaces/http/router.go` | `/api/v1/ledger` exists only when ledger composition succeeds; individual admin operations add role checks. |
| Payments | `cmd/server/main.go` | Payment routes are registered conditionally; exact coverage depends on the remainder of composition and configuration. |

## Client inventory scan — scope and limits

A source-literal scan was performed across `apps/consumer_app/lib`, `apps/driver_app/lib`, and `apps/admin_console/src`. It found endpoint-like references across all three applications, including:

- Consumer: auth, legal/consent, Nidus ride and split-fare operations, payment methods, safety, analytics event submission, chat, notifications, and other product flows.
- Driver: auth, ride lifecycle, active rides, driver profile/status, vehicle, stats, earnings, documents, profile picture, and location updates.
- Admin console: ledger API references.

This scan is a discovery aid, not a complete endpoint count: paths may be assembled from base URLs, interpolation, constants, repositories, or API client wrappers. Each reference must be resolved to its effective HTTP method, full path, request/response model, auth requirements, error handling, and feature-flag behavior before contract acceptance.

## Decisions and blockers

1. Designate the authoritative API contract source and define how OpenAPI stays synchronized with mounted routes.
2. Build a complete method/path inventory for all three clients, resolving dynamic path construction and common API-client wrappers.
3. Map each client operation to an actually mounted handler, including feature-gated behavior and expected disabled-state UX.
4. Add contract tests for method/path, payload, response/error schema, auth/role checks, and relevant feature-flag combinations.
5. Do not add speculative aliases or placeholder-success endpoints to make the inventory appear complete.
6. Verify routes through the running server and gateway after static contracts are reconciled.

## Phase 0 status

This finding increases confidence in the static audit but does not close Phase 0. Clean-checkout Go/Flutter baselines, live migration validation, full client/server contract coverage, authorization/resource-boundary tests, and deployment-path runtime validation remain outstanding.
