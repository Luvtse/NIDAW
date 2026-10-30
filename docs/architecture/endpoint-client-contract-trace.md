# Endpoint-to-Client Contract Trace (Static Audit)

## Scope and evidence

This inventory was produced from static inspection of `services/api/cmd/server/main.go`, the Go module tree, and literal API path references under `apps/consumer_app/lib`, `apps/driver_app/lib`, and `apps/admin_console/src`. It is not a runtime contract test. Dynamically constructed paths, generated clients, and endpoints used only by remote integrations may be absent.

## Observed client endpoint families

| Endpoint family | Observed client use | Runtime evidence | Audit status |
|---|---|---|---|
| `/api/v1/auth/*` | Consumer and driver auth/session flows | Auth router mounted at `/` in `services/api/cmd/server/main.go` | Route registration observed; every route's authorization semantics still require tests |
| `/api/v1/nidus/rides*`, `/api/v1/rides*` | Consumer ride request, estimate, active ride; driver ride operations | Nidus router mounted at `/` in `services/api/cmd/server/main.go` | Main product route family mounted; optional routes depend on feature flags |
| `/api/v1/drivers/*`, `/api/v1/driver/rides/*` | Driver profile, status, location, earnings, documents, ride operations | Nidus router construction is mounted; handler-level mapping requires router inspection | Static client references observed; contract and authorization tests outstanding |
| `/api/v1/nidus/payment-methods*` | Payment method management | Payment-method service injected into Nidus router | Route availability depends on the router and feature/config behavior; verify disabled/enabled states |
| `/api/v1/promotions/*` | Promotion redemption and user promotions | Promotions service injected only when `EnablePromotions` is true | Conditional route family; tests must cover both flag states |
| `/api/v1/nidus/split*` | Split-fare workflows | Split service injected only when `EnableSplitFare` is true | Conditional route family; verify client fallback when disabled |
| `/api/v1/nidus/rides/*/price-extension` | Price extension negotiation | Feature-flagged in composition comments and dependencies | Conditional route family; test disabled state and status behavior |
| `/api/v1/chat*` | Chat and ride messages | Chat application/infrastructure/HTTP packages imported in composition root | Registration exists in code; full middleware and consumer mapping still needed |
| `/api/v1/consent*`, `/api/v1/legal/*` | Consent and legal-document workflows | Legal consent routes registered in composition root | Registration observed; admin/resource authorization needs route-level verification |
| `/api/v1/ledger*` | Ledger balance, top-up, withdrawals, transactions, disputes | Ledger router mounted only when `EnableInternalLedger` is true | Feature-gated; verify client UX and disabled behavior |
| `/api/v1/analytics/events` | Analytics event submission | Analytics module exists; route registration needs full trace | Client reference observed; owner and runtime handler must be confirmed |
| `/api/v1/selfies*` | Driver identity/selfie workflow | Selfie module imported in composition root | Registration/feature state requires router-level confirmation |
| `/ws` | Real-time ride/driver updates | Nidus WebSocket hub is constructed and Nidus router mounted | WebSocket auth and subscription authorization are configured; end-to-end event flow remains to be tested |
| Haven accommodation APIs | No verified consumer endpoint family established in this scan | Gateway route configuration exists; no corresponding Haven module directory was found | Not proven operational; avoid claiming working accommodation booking |
| Vorax food APIs | No verified consumer endpoint family established in this scan | Gateway route configuration exists; no corresponding Vorax module directory was found | Not proven operational; avoid claiming working food ordering |
| Logix freight APIs | No verified client endpoint family established in this scan | `internal/modules/logix` exists but is not imported by the composition root inspected | Module presence only; runtime product availability not established |
| Corpus corporate travel APIs | No verified client endpoint family established in this scan | `internal/modules/corpus` exists but is not imported by the composition root inspected | Module presence only; runtime product availability not established |

## Client contract cautions

- Literal endpoint search is an initial inventory, not proof of all usage. Search for generated API clients and constructed paths before declaring coverage complete.
- A path mentioned by a client does not prove the server mounts it. A route mounted by the server does not prove a client uses it or that authorization is correct.
- Feature flags can intentionally make routes unavailable. Contract tests should verify both enabled and disabled behavior for money-affecting or operational features.
- API response shape, error codes, authentication requirements, and pagination must be extracted from handlers and tests before moving packages or generating shared contracts.

## Required follow-up tests

1. Generate or maintain a route registry from the actual Chi router and compare it with client references.
2. Add provider/consumer contract tests for auth, Nidus ride lifecycle, driver operations, payment methods, promotions, chat, consent, ledger, and WebSocket events.
3. Add tests for each feature-flagged route in both enabled and disabled states.
4. Add explicit negative authorization tests for rider/driver ownership, admin-only actions, and tenant/resource boundaries.
5. Do not expose Haven, Vorax, Logix, or Corpus as available products until concrete routes, use cases, persistence ownership, and workflow tests prove them usable.

## Phase 0 follow-up — gateway-to-runtime reachability (static source trace)

This section distinguishes route configuration from a proven live request path. Evidence was checked in `platform/gateway/kong/kong.yml`, `platform/gateway/routes/*.yaml`, `platform/docker/compose/dev.yaml`, `platform/docker/compose/prod.yaml`, `config/nginx/nginx.conf`, and `services/api/cmd/server/main.go`. No gateway or backend container was started for this audit.

| Entry point | Static evidence | Finding and impact | Required verification/action |
|---|---|---|---|
| Kong backend DNS | Kong declarative services use `http://nidaw-backend:8080`; Compose service key is `backend`, while `container_name` differs between dev (`nidaw-backend-dev`) and prod (`nidaw-backend-prod`). | `nidaw-backend` is not the declared Compose service DNS name. Unless an external network alias is configured elsewhere, Kong cannot resolve its configured upstream. This is a concrete configuration inconsistency, not a proven live outage. | Confirm all network aliases and deployment targets. Prefer the Compose service DNS name (`backend`) for the Compose path, or configure an explicit stable alias and validate it with Kong and Compose. Do not edit the target blindly until the canonical deployment path is selected. |
| Kong path composition | Kong services define a service URL path such as `/api/v1/nidus`; associated routes include full paths such as `/api/v1/nidus/rides` and set `strip_path: false`. | The service path and preserved route path appear liable to combine into a duplicated upstream path. Exact proxy URI behavior must be confirmed against the deployed Kong version/config. | Run `kong config parse`, then an integration request against a known backend route and inspect the upstream request path. Simplify to one path-rewrite strategy after preserving all existing routes. |
| Nginx backend DNS | `config/nginx/nginx.conf` defines upstream `backend:8080`; Compose service key is `backend`. | The name is aligned with Compose service discovery, subject to both containers sharing the same network. The configuration also defines `/health` and `/ready` responses at the proxy, which do not prove backend readiness. | Test container-network resolution and distinguish proxy liveness from backend readiness in deployment probes. |
| Active Go API | `services/api/cmd/server/main.go` builds one Chi router and mounts auth, legal/consent, Nidus, optional ledger, and other handlers. `cfg.Server.Port` defaults to `8080`. | This is the active modular-monolith composition root evidenced in the source. A route file or service definition alone does not prove a separate product service exists. | Generate a complete method/path registry from the mounted routers and compare it with gateway route coverage and client calls. |
| Nidus | `nidushttp.NewRouter(nidusDeps)` is mounted at `/`; Nidus dependencies include DB, event bus, auth, location cache, matching, ETA, pricing, and optional features. | Nidus is wired into the main backend. Feature flags can still omit individual routes. | Exercise enabled and disabled states and test ownership/auth checks for rider, driver, and WebSocket access. |
| Ledger and provider callbacks | Ledger routes mount only when `ledgerComps != nil`; webhook routes and top-up/payout workers additionally require a configured `ledgerResolver`. | Ledger API and provider rails have separate runtime conditions. An enabled-looking client screen or gateway route does not guarantee configured provider processing. | Document required feature flags and provider environment variables; integration-test both configured and unconfigured states without real-money side effects. |
| Logix and Corpus | Source packages exist, but neither is imported/mounted by the inspected `main.go`. | No active HTTP reachability is established for these product packages in this composition root. | Search and validate alternate entry points/deployment manifests before classifying them as runtime products. |
| Haven and Vorax | Kong route files and service entries exist, but no corresponding Go product module was found in the inspected repository. | Gateway configuration describes intended upstream behavior, not an implementation or healthy upstream. | Identify a real upstream deployment and ownership, or mark these routes as planned/stale and keep them out of availability claims. |

### Runtime request-chain summary

- **Flutter consumer/driver → API:** client repositories call `/api/v1/...` through their configured `ApiClient` base URL. The deployment may route these requests through Kong or Nginx depending on the selected environment; the repo does not establish that every environment uses the same ingress.
- **Kong path:** client request → Kong route match → service/upstream URI → Go server router → module router/handler → handler-level auth/validation and persistence. The configured upstream DNS mismatch and possible path composition issue must be resolved and tested before claiming this chain works end to end.
- **Nginx path:** client request → Nginx `/api/` or `/ws` proxy → `backend:8080` → Go router. The proxy's `/health` and `/ready` endpoints are local static responses, not checks of backend/database/broker health.
- **Authorization:** global Go middleware in `main.go` includes request ID, real-IP, logging, panic recovery, timeout, and metrics. Authentication is not globally applied to every route; auth routers and protected module routes apply auth at router/handler level. Each mounted route still needs a verified policy.

### Phase 0 acceptance impact

The gateway-to-runtime trace is **partially complete, not accepted**. The Kong DNS mismatch is a high-priority static finding. Kong URI behavior, actual ingress selection, all route-level security rules, and all five product runtime paths still require explicit validation. No application runtime code was changed as part of this audit update.


## Phase 0 follow-up — Nidus route security and gateway coverage matrix

This matrix is derived from the current `services/api/internal/modules/nidus/interfaces/http/router.go` registration code and the corresponding gateway declarative configuration. It is intentionally a route-family matrix rather than a claim that every individual handler's resource-ownership logic has passed tests.

| Route family | API router protection observed | Gateway declaration observed | Static gap / action |
|---|---|---|---|
| `GET /health` | Nidus router global middleware; no JWT group | Not established as a public Kong route in this trace | API handler pings PostgreSQL; ensure only intended internal/probe ingress exposes it. |
| `GET /ready` | Nidus router global middleware; no JWT group | Not established as a public Kong route in this trace | Handler returns a static success response; it does not test dependencies. Do not use it as dependency readiness without changing its semantics. |
| `POST /api/v1/nidus/rides/estimate`, `GET /api/v1/nidus/rides/estimates` | Explicit public group | Estimate has a gateway route; estimates route coverage not established | Confirm both paths and methods are deliberately public and rate-limited. |
| `/api/v1/nidus/rides/*` | Protected group applies `AuthRequired` and `ExtractUserToContext` | Several CRUD/lifecycle routes exist in Kong; not all API routes have matching gateway entries | Compare every method/path, especially accept/start/complete, cancellation quote, email receipt, cash collection, destination change, price extension, and split-fare. Verify handler-level owner/role checks. |
| `/api/v1/nidus/drivers/*` | Protected group applies `AuthRequired` and `ExtractUserToContext` | Nearby and detail routes are declared; pending-rides coverage not established | Confirm driver identity and role restrictions for pending offers, location visibility, and profile details. |
| `/api/v1/nidus/payment-methods/*` | Protected group; routes only when `PaymentMethodSvc != nil` | Full gateway coverage not established | Verify flag/config state and ensure create/delete/default operations are restricted to the authenticated owner. |
| `/api/v1/promotions/*` | Protected group; routes only when service exists and promotions enabled | Gateway coverage not established in this trace | Verify owner binding, redemption replay behavior, and explicit disabled-state response. |
| `/api/v1/nidus/location/*` | Protected group | Update route is declared in Kong; driver-location read coverage requires comparison | Verify driver can only update own location and readers satisfy ride/dispatch authorization. |
| `POST /api/v1/split/{token}/accept` | Deliberately outside JWT requirement; random invite token is the authorization capability; optional user context extracted | Gateway coverage not established | Test token entropy, expiry, single-use/replay behavior, and authorization to the targeted split. |
| `GET /ws` | Route is mounted when `WSHub` exists; hub uses subscription authorizer configured in `main.go` | Gateway WebSocket upgrade/routing configuration not established here | Validate upgrade headers, token validation, origin policy, and per-room participant authorization end to end. |

### Cross-cutting security facts and limits

- The Nidus router applies request ID, real-IP handling, structured logging, panic recovery, a 30-second timeout, CORS policy, and an IP rate limiter globally. This is not a substitute for authentication, authorization, or business-specific quotas.
- Protected Nidus route groups apply `AuthRequired` and `ExtractUserToContext`; this establishes authentication middleware registration, not correctness of every handler's resource ownership checks.
- Some routes are conditionally mounted based on injected dependencies or feature flags. The gateway must not advertise them as operational unless the selected deployment enables and configures them.
- Kong configuration contains services pointing to `http://nidaw-backend:8080` while the inspected Compose service key is `backend`. No matching alias was found in the inspected Compose definition. Validate the complete network definitions before changing this configuration.
- Kong services set a URI path prefix and their routes preserve full paths (`strip_path: false`). Treat this as a suspected path composition defect until `kong config parse` and a live upstream request prove the actual forwarded path.

### Phase 0 acceptance status from this trace

**Not accepted.** Static registration and middleware evidence has improved, but a generated complete method/path registry, handler-level authorization tests, client-to-server contract comparison, Kong parsing, and live gateway-to-backend tests remain outstanding. External tool absence must be recorded as a verification blocker rather than converted into a pass.


## Phase 0 follow-up — Deployment-specific Kong upstream reconciliation

A deeper comparison of the checked-in Compose overlays and Kubernetes Service corrects an overly broad earlier statement that the Kong upstream hostname is simply wrong in every deployment. The finding is deployment-specific:

| Deployment path | Backend DNS identity evidenced in source | Kong target | Static assessment |
|---|---|---|---|
| Compose development (`platform/docker/compose/dev.yaml`) | Compose service key `backend`; container name `nidaw-backend-dev` | `nidaw-backend:8080` | **Mismatch candidate confirmed in checked-in definitions:** container names are not the Compose service DNS name. No `nidaw-backend` network alias was found in the inspected overlay. |
| Compose production (`platform/docker/compose/prod.yaml`) | Compose service key `backend`; container name `nidaw-backend-prod` | `nidaw-backend:8080` | Same mismatch candidate, unless an alias is supplied externally or by an uninspected override. |
| Kubernetes base | Service object `nidaw-backend`, port 80 targeting backend port 8080 | `nidaw-backend:8080` | DNS name exists in Kubernetes, but the configured port does not match the Service object's declared port 80. A pod-to-Service request should normally use `nidaw-backend:80`; direct pod targeting is not established. |

The repository does not establish one canonical deployment path. The Compose and Kubernetes findings must not be conflated. Resolve this by selecting the supported deployment mode and aligning Kong's target host/port with that mode, then validate the rendered config and make an actual request. Do not infer runtime success from a matching name alone.

### URI path composition remains a separate blocker

In `platform/gateway/kong/kong.yml`, services declare path prefixes such as `/api/v1/nidus`, while routes preserve full request paths such as `/api/v1/nidus/rides` with `strip_path: false`. This is a suspected upstream URI composition defect and must be tested with the exact Kong version/config semantics; do not treat it as a proven runtime failure without a parsed config and observed upstream request URI.

### Configuration source-of-truth risk

The separate files under `platform/gateway/routes/` contain route declarations that overlap route definitions embedded in `platform/gateway/kong/kong.yml`. Compose mounts `kong.yml` as the declarative config; the inspected setup does not show the route fragments being included automatically. Therefore, editing a fragment may not change the running gateway unless a documented generation/merge step exists. The authoritative source and any generation mechanism must be identified before gateway edits.

### Required verification

1. Choose the supported deployment target (Compose or Kubernetes) for local/integration verification.
2. Parse the actual rendered Kong declarative file with the matching Kong version.
3. Check DNS resolution and TCP connectivity from the Kong container/pod to the selected backend Service.
4. Capture the upstream request URI for a known route and confirm it matches the Go router path exactly.
5. Verify gateway route/method coverage against the active Go router registry.
6. Record external overrides or aliases as explicit deployment configuration rather than assumptions.


## Phase 0 follow-up — client/router/Kong method-path discrepancy pass

This pass compares literal client endpoint references, explicit Nidus Chi route registrations, and the checked-in `kong.yml`. It is a static discrepancy pass; it does not infer runtime aliases, generated paths, or handler authorization from a path string alone.

### Confirmed discrepancies requiring resolution

| Client or gateway reference | Server registration evidence | Assessment | Next action |
|---|---|---|---|
| Client uses `/api/v1/rides/{rideID}/accept`, `/start`, `/complete` and `/api/v1/rides/active` | Nidus router explicitly registers ride lifecycle under `/api/v1/nidus/rides/{rideID}/...`; the inspected Nidus router does not register the shorter `/api/v1/rides/*` alias | **Potential client/server contract mismatch.** A separate mounted router or rewrite may provide the legacy path, but this pass did not establish one for these exact paths. | Search all mounted routers and gateway rewrites for the shorter aliases. If none exists, migrate client callers or add explicit compatibility routes with tests; do not silently assume aliases. |
| Client references `/api/v1/nidus/rides/active` | Nidus router registers `GET /api/v1/nidus/rides/` and `GET /api/v1/nidus/rides/{rideID}` but no literal `/active` route in the inspected router | **Potential missing endpoint.** Chi may route `active` as `{rideID}` and fail UUID parsing rather than provide an active-rides response. | Inspect the client repository's response expectations and ride-list query support. Add an explicit route only if the intended contract requires it. |
| Client references `/api/v1/nidus/safety` | No safety route appears in the inspected Nidus router registration block | **Unverified/missing route candidate.** | Search the full composition root and other routers, then either establish the owning handler or correct the client path/feature availability. |
| Client references `/api/v1/driver/rides/{rideID}/pre-selfie` | Nidus router's shown ride and driver groups do not register this path; server composition includes a selfie module and a pre-selfie attachment adapter | **Mount/contract needs verification.** The DTO attachment feature does not itself prove the redemption endpoint exists at the client path. | Trace selfie router registration and exact path, auth policy, token redemption, and expiry behavior. |
| Kong routes define Haven and Vorax endpoints | Inspected Go composition mounts Nidus and shared modules; no Haven/Vorax Go product router is mounted | **Gateway intent is not a working product implementation.** | Do not expose these routes as operational until actual product routers/upstreams are implemented and workflow-tested. |
| Kong Nidus service has `path: /api/v1/nidus`; routes preserve full `/api/v1/nidus/...` paths (`strip_path: false`) | Backend router expects paths beginning `/api/v1/nidus/...` | **Likely path-prefix duplication risk.** | Verify exact URI composition with the repository's supported Kong version before changing path strategy. Prefer a single clear rewrite policy and integration tests. |

### Additional method/path coverage notes

- The Nidus router explicitly registers `GET /api/v1/nidus/rides/estimates`, but the visible Kong Nidus service route list has `POST /rides/estimate` and does not establish a matching route for `GET /rides/estimates`.
- The backend registers lifecycle actions (`accept`, `start`, `complete`), cancellation quote, email receipt, optional cash collection, optional destination change, optional price extension, and optional split-fare operations. The visible embedded Kong routes do not cover every one of these methods/paths.
- The backend registers `/api/v1/nidus/location/driver/{driverID}` for location reads, while the visible Kong declarations establish `/location/update` but not the read route.
- The route fragments under `platform/gateway/routes/` overlap embedded routes in `kong.yml`, but Compose mounts the embedded declarative file. The fragments must not be treated as active gateway routes unless a documented build/merge process is shown.

### Limits and required acceptance evidence

This audit did not modify application routing or client calls because compatibility aliases and feature intent need confirmation first. Acceptance requires: (1) a complete method/path registry generated from all mounted routers; (2) literal and dynamically constructed client path inventory; (3) gateway path/method comparison against the selected deployment config; (4) contract tests for each confirmed discrepancy; and (5) integration tests proving the forwarded URI reaches the intended handler. No live gateway/backend request was run for this pass.

## Phase 0 continuation — confirmed client/API contract findings

See `phase-0-confirmed-client-contract-findings.md` for evidence and remediation sequencing. Confirmed source-level issues include legacy driver ride paths not registered by the inspected Nidus router, active-ride clients targeting `/active` without a dedicated handler, consumer safety API calls without a matching route group in the active composition root, and a pre-selfie multipart field mismatch (`selfie` client versus `image` server). The pre-selfie upload route itself does exist under `/api/v1/driver/rides/{rideId}/pre-selfie` when its feature flag is enabled; prior language implying that exact upload route was absent should be read as unverified before this trace. No behavior was changed pending contract and compatibility decisions.
