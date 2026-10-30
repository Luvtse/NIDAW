# Phase 0 — Kong routes versus mounted Go routes (2026-10-22)

## Status

**Static reconciliation only; gateway contract is not accepted.** This compares `platform/gateway/kong/kong.yml` with the source-derived mounted-route registry in `phase-0-mounted-route-registry-static-2026-10-22.csv`. It is not a Kong runtime route walk, does not render Kong's effective configuration, and does not prove a request can reach a handler.

## Inventory

- Kong declarative configuration contains 6 Services and 24 Route objects.
- The static Go registry contains 79 method/path records.
- Kong currently defines routes for Nidus, Haven, Vorax, auth, health/readiness, and WebSocket traffic.
- The static active-composition registry contains no route records owned by Haven or Vorax. Earlier composition audit evidence also says Corpus and Logix are not imported/mounted in the active server composition. Therefore the Haven/Vorax Kong routes are not backed by a corresponding route in this registry; this must be resolved against intended feature/deployment topology before exposing them.

## Findings

### 1. Kong advertises Haven and Vorax route families without a matching active-composition route record

Kong defines four Haven routes (`GET /api/v1/haven/hotels`, hotel detail, and GET/POST `/api/v1/haven/bookings`) and five Vorax routes (restaurant listing/menu and order create/list/tracking). None maps to a route in the current 79-record mounted registry.

**Risk:** Gateway configuration may advertise product endpoints that the active Go composition does not serve, resulting in upstream 404s or misleading product availability. This is a static mismatch, not proof that the underlying modules or handlers do not exist elsewhere in the repository.

**Required decision:** For each route, either prove and test the intended handler is mounted in the selected composition, or explicitly mark the route unavailable and remove/disable it from that deployment's gateway configuration. Do not add placeholder handlers to satisfy the comparison.

### 2. The Nidus ride-detail gateway pattern is narrower than the Go route template

The Kong route for ride detail restricts the identifier to a UUID-shaped hexadecimal pattern. The mounted route registry describes `{rideID}` as a generic path parameter. Static evidence does not establish that all valid IDs are UUIDs or that the Kong regex matches the handler's accepted ID format.

**Risk:** Valid IDs outside the Kong pattern may be rejected at the gateway even when the handler accepts them. Conversely, broadening the gateway pattern without confirming handler validation could widen the accepted surface.

**Required decision:** Confirm the domain ID format and align the gateway expression with handler validation; test valid and invalid IDs through Kong.

### 3. The WebSocket gateway route uses `/ws`, while the Go registry records `/api/v1/ws`

The Kong WebSocket Route uses `/ws`; the mounted-route registry includes `GET /api/v1/ws`. The Nidus router also registers a WebSocket endpoint under its product route group, so this may represent a separate or stale route definition. The existing static registry does not establish a one-to-one mapping for the Kong `/ws` route.

**Risk:** WebSocket clients may connect to a gateway path that has no matching mounted handler, or the gateway may be intended to target a different route than the one recorded.

**Required decision:** Trace the actual `r.Get` registration, group prefix, Kong service path, and client URL together. Add an authenticated and unauthenticated handshake test against the selected gateway path. Do not infer the effective upstream URI from YAML alone.

### 4. Many registered Go routes have no explicit Kong Route object

The conservative comparison finds 65 of the 79 mounted method/path records without an explicit matching Kong route. Examples include legal/consent endpoints, many Nidus lifecycle/payment-method operations, chat, notifications, telephony, selfie, ledger, payment webhook, promotions, and metrics.

**Risk:** These endpoints may be intentionally internal or intentionally omitted, or they may be inaccessible through the configured gateway. The current files do not provide an explicit allowlist that distinguishes those cases.

**Required decision:** Create a reviewed exposure matrix for every route family: public through Kong, internal-only, feature-gated, or deliberately unsupported. Validate the matrix against clients and gateway configuration. Do not automatically expose every mounted handler.

### 5. Existing service-path and route-path overlap remains unresolved

The existing deployment-path report documents that the Nidus/Haven/Vorax Kong Services define product-prefix `path` values while their Routes preserve paths containing the same prefix (`strip_path: false`). This reconciliation does not change that configuration because its effective forwarded URI must be verified against the deployed Kong version and chosen topology.

## Static comparison details

A conservative path comparison was made against the source-derived CSV. Literal paths and straightforward path patterns can be compared statically, but a template such as `{rideID}` is not equivalent evidence to a gateway UUID regex. The count of uncovered records is therefore a **review queue**, not a claim that every uncovered route is broken. Some routes may intentionally bypass Kong, be protected by a different ingress, be feature-gated, or be represented differently by path normalization.

The full candidate mounted-route inventory remains `phase-0-mounted-route-registry-static-2026-10-22.csv`. The Kong source of truth for this pass is `platform/gateway/kong/kong.yml`.

## Required next steps

1. Select and document the canonical runtime topology and the intended public/internal gateway exposure policy.
2. Reconcile every Kong Route with a mounted handler and every mounted route with an explicit exposure decision.
3. Resolve Nidus ride ID format and the `/ws` versus `/api/v1/ws` discrepancy from source and client URL construction.
4. Resolve service-path/route-path composition using a Kong integration test that asserts the exact upstream URI.
5. Render/validate Kong configuration with the supported Kong tooling, then test representative 2xx, 401/403, 404, and 5xx paths through the gateway.

## Acceptance

Phase 0 remains open. This pass identifies route exposure and reachability questions; it does not prove live gateway behavior, authentication, handler availability, or upstream URI composition.
