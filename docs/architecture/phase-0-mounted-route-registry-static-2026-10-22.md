# Phase 0 — Static mounted-route registry and security scope (2026-10-22)

## Status

This source-derived registry contains 79 candidate route records. It is not a runtime walk of the Chi router. Prefixes were composed from inspected router registrations. Full CSV: `phase-0-mounted-route-registry-static-2026-10-22.csv`.

## Limitations

- Feature/dependency-gated modules may not be mounted in a given environment.
- This registry does not prove payload/response DTOs, status/error schemas, or actual runtime matching and slash redirects.
- It captures visible middleware scope, not a complete authorization proof. Resource ownership and handler-level checks still require tests.
- Payment webhook path was verified as `POST /api/v1/payments/webhooks/{provider}` from `WebhookHandler.Register`. It is a public provider callback; signature verification in the adapter is the security gate, not JWT. Runtime signature and replay tests remain required.
- `GET /ready` in the Nidus router returns a static response and must not be treated as dependency readiness.

## Confirmed client-contract risks

1. Nidus ride operations are registered under `/api/v1/nidus/rides/...`; no legacy `/api/v1/rides/...` aliases were found in the inspected router.
2. No explicit `GET /api/v1/nidus/rides/active` route is registered. Generic `/{rideID}` does not implement active-ride lookup.
3. Client references for driver profile/status/stats/earnings/documents/vehicle do not appear among these registered route families.
4. `/api/v1/nidus/safety` and `/api/v1/analytics/events` were not found in the inspected active composition.
5. Admin paths are relative to `/api/v1/ledger` by default; `VITE_API_BASE` can override the base.
6. Notifications, chat, telephony, selfie, and ledger depend on feature flags or composition dependencies.
7. Global middleware includes request ID, real IP, logging, recovery, timeout, and observability. Per-handler authorization remains a separate verification layer.

## Security observations

- Nidus protected routes use authentication and user-context extraction; public fare estimates and token-authorized split acceptance are outside that group.
- The WebSocket registration comment says the route sits outside `AuthRequired`, but the source places `r.Get("/ws", ...)` inside the protected route group. This source/comment contradiction must be resolved deliberately; runtime handshake tests should cover authenticated and unauthenticated clients. Subscription authorization is wired to a Postgres ride authorizer, but room-isolation tests remain outstanding.
- Ledger uses JWT middleware; several admin operations also invoke handler-level admin checks.
- Health and metrics exposure must be aligned with gateway/network policy.

## Next actions

1. Add/execute a regression check for WebSocket middleware placement and document the intended handshake auth model.
2. Add a runtime Chi route walk/export where composition dependencies permit and compare it to this registry.
3. Reconcile client operations with routes and OpenAPI; verify DTOs before adding spec paths.
4. Test ride ownership, admin mutations, selfie redemption, split tokens, WebSocket room isolation, and feature flags.
5. Run Go and integration tests in a dependency-enabled environment with disposable PostgreSQL.

## Validation performed

- CSV row count and required columns were checked locally; the registry contains 79 source-derived route records.
- `go test ./internal/modules/nidus/interfaces/http ./internal/modules/ledger/interfaces/http ./internal/modules/ledger/infrastructure/adapters` was attempted with a 90-second limit. Go attempted to download dependencies, but the command timed out before tests ran. This is a blocked validation, not a test pass.
- The output ZIP passed `unzip -t` archive integrity validation.

## Acceptance

Phase 0 remains open. This static registry improves traceability but does not prove runtime routing, full client contract alignment, migration execution, or authorization correctness.
