# Phase 0 — Current Source Validation and Baseline Recheck

## Status

**Phase 0 remains open.** This report rechecks the current reconciled archive against the master roadmap. It does not treat prior documentation or an earlier phase label as proof of acceptance. The repository is statically inspectable, but required clean-checkout Go/Flutter, live PostgreSQL, and deployment-runtime checks remain blocked in this environment.

## Scope and method

- Repository root inspected: `N-main/` from `NIDAW-roadmap-reconciled.zip`.
- Backend entry point: `services/api/cmd/server/main.go`.
- Go module: `services/api/go.mod` (`nidaw-backend`, declared Go 1.19); installed toolchain reports Go 1.23.2.
- Client manifests: `apps/consumer_app/pubspec.yaml`, `apps/driver_app/pubspec.yaml`, `apps/admin_console/package.json`.
- Infrastructure examined statically: GitHub Actions, `platform/docker/compose/`, `platform/gateway/`, `platform/kubernetes/`, `platform/helm/nidaw/`, and `infrastructure/`.
- Database assets examined statically: `data/migrations/postgres/`, `data/migrations/timescale/`, and `data/seeds/`.
- No production environment, credentials, deployed upstream, or live database was available for inspection.

## Verified inventory

| Area | Evidence | Finding / impact | Required action |
|---|---|---|---|
| Go backend | One `go.mod` under `services/api`; composition root at `cmd/server/main.go` | The repository has one Go module and one broad server composition root; this is consistent with the intended modular-monolith starting point, but module lifecycle ownership is not yet fully isolated. | Build the full import/runtime graph and then refactor only after Phase 3 boundaries are accepted. |
| Client applications | Flutter consumer and driver manifests; React/TypeScript/Vite admin manifest | Three native app toolchains are present. Flutter SDK is absent in this environment. | Validate each app with its native toolchain in a dependency-enabled environment. |
| Product source directories | `nidus` has domain/application/infrastructure/HTTP code and tests; `logix` contains a shipment entity and three application service files; `corpus` contains a corporate account entity and a booking command; no `haven` or `vorax` Go module directories exist. | File presence is not equivalent to complete workflows. Haven/Vorax gateway routes and analytics objects do not prove deployed implementations. Logix/Corpus code is not mounted by the inspected main composition root. | Trace all entry points and downstream targets; define missing workflows and avoid claiming product completeness. |
| Runtime wiring | `main.go` imports/mounts auth, Nidus, notifications, chat, legal/consent, optional ledger/payment rails, and other handlers. It does not import/mount Corpus or Logix. | Some existing product source is not demonstrably reachable through the active Go server. | Verify alternate runtime/deployment targets; if none exist, record as unmounted implementation gaps. |
| Payment naming | Both `internal/modules/payment` and `internal/modules/payments` exist. `main.go` uses `payments` for payment-method registry behavior; provider webhook/top-up/payout wiring is under ledger adapters. | Similar names conceal different responsibilities and increase the risk of implementing changes in an inactive path. | Document ownership and consumers before consolidating or changing either package. |
| Shared capabilities | `ledger`, `notifications`, `promotions`, `pricing`, `auth`, `identity`, `shared/database`, `shared/eventbus`, and shared provider integrations exist. | These are candidates for shared capabilities, but package boundaries and cross-domain writes/imports still need full review. | Assign authoritative owners and expose narrow application contracts. |
| API/gateway | `services/api/api/openapi.yaml`; Kong route files for Nidus, Haven, Vorax; gateway upstream definitions for Haven/Vorax. | The contract, gateway, server, and actual upstream runtime cannot yet be shown to agree. | Build a complete method/path → handler → middleware → client/upstream trace and contract tests. |
| Database migrations | PostgreSQL migrations `001`–`018`, including seed migration `003`, payment migrations `015`/`016`, test fault injection `017`, and ledger outbox `018`; Timescale migration `001`. | Existing ownership inventory is heuristic. `015` and `016` overlap payment schema definitions; the newer `018` migration must be included in all current inventories. | Validate from an empty PostgreSQL database and representative upgrade snapshot; preserve already-applied migration history. |
| Deployment | Compose, Kong, Helm, raw Kubernetes/Kustomize, Terraform, and CI deployment workflows exist. | Multiple deployment mechanisms exist; static files do not establish which is authoritative or live. | Choose and document supported deployment paths, then validate rendering and startup using the actual tools. |
| Security | Shared auth/security/middleware code and gateway rate-limiting assets exist. | Existence does not prove route-level authorization, resource ownership checks, webhook signature verification, tenant isolation, or safe sensitive logging. | Complete route-by-route authorization and tenant isolation tests; audit provider callback authentication and logging. |
| Future contracts packages | No canonical `packages/api-contracts/`, `packages/event-contracts/`, or `packages/shared-config/` directories in this snapshot. | Phase 1's target package locations are not yet represented; avoid creating empty scaffolds. | Create only when real maintained schemas/configuration can be moved or authored as part of Phase 6. |

## Five-product capability matrix (source evidence, not completeness claims)

| Product | Present evidence | Current classification | Material gaps to prove |
|---|---|---|---|
| **Nidus** | Ride/driver entities, ride lifecycle and dispatch commands, matching/pricing/ETA services, location cache, HTTP handlers, WebSocket handlers, and focused Go tests under `services/api/internal/modules/nidus/`; router mounted in `main.go`. | Substantial partial implementation and active runtime integration. | Full lifecycle invariants, concurrent dispatch acceptance, location privacy, pricing/payment consistency, authorization, client journey, and integration-test results. |
| **Haven** | `platform/gateway/routes/haven.yaml`, gateway upstream references, and hotel analytics SQL. No `internal/modules/haven/` directory found. | Backend reservation workflow not established by current Go module inventory. | Provider/property/room/inventory model, holds, reservation state machine, concurrency-safe no-double-booking guarantee, payment/refund coordination, API handler and active upstream. |
| **Vorax** | `platform/gateway/routes/vorax.yaml`, gateway upstream references, and order analytics SQL. No `internal/modules/vorax/` directory found. | Backend merchant/order/delivery workflow not established by current Go module inventory. | Merchant/menu/cart/checkout, separate order and delivery state machines, courier assignment, proof of delivery, refunds/settlement, API handler and active upstream. |
| **Logix** | `internal/modules/logix/domain/entities/shipment.go` plus customs, error, and load-matching application services. No registration in inspected `main.go`. | Limited library/source footprint; runtime workflow not established. | Persistence/repositories, unique stable shipment IDs, carrier callbacks, documents, shipment lifecycle, billing, routes, tests, and caller/runtime. |
| **Corpus** | `internal/modules/corpus/domain/entities/corporate_account.go` and `application/commands/create_booking.go`. No registration in inspected `main.go`. | Limited library/source footprint; corporate travel orchestration not established. | Tenant/org enforcement, policy/approval workflow, audit, budgets, cross-product orchestration, compensation/partial success, persistence, routes, tests, and runtime caller. |

## Additional gateway-to-runtime findings (static)

A follow-up trace of the gateway and deployment files found a material inconsistency: `platform/gateway/kong/kong.yml` targets `nidaw-backend:8080`, while the checked-in Compose files declare the service as `backend` and use environment-specific container names (`nidaw-backend-dev` / `nidaw-backend-prod`). No explicit `nidaw-backend` network alias was found in the inspected Compose snippets. Treat this as a configuration defect candidate until all deployment aliases are checked; do not claim the Kong path is operational.

The Kong services also declare a URI path prefix (for example `/api/v1/nidus`) while matching full request paths and setting `strip_path: false`. This may duplicate path segments upstream depending on Kong URI construction. It must be resolved with `kong config parse` and a real request-path integration test, not by assumption.

The Nginx upstream `backend:8080` aligns with the Compose service key `backend`, but Nginx `/health` and `/ready` handlers return static success and therefore do not prove backend or dependency readiness. The API server is configured from `cfg.Server.Port` (default `8080`). The exact production ingress path remains unverified. The detailed evidence and remediation sequence are in `endpoint-client-contract-trace.md`.

## Current environment verification

| Check | Result | Evidence / limitation |
|---|---|---|
| ZIP archive | Pass | Archive integrity check passed before extraction. |
| Go product module gate | **Fail, intentionally fail-closed** | Direct cross-product imports were not found, but the guard now exits non-zero because Haven and Vorax module directories are absent. It checks module presence and direct imports only, not runtime/data/event boundaries. See `phase-0-product-module-gate-hardening-2026-10-23.md`. |
| Static schema ownership inventory | Pass as a generator | `python3 scripts/architecture/inventory-schema-ownership.py` completed. Its output is a candidate inventory, not authoritative ownership approval. |
| Migration runner shell syntax | Pass | `bash -n scripts/migrations/migrate-up.sh scripts/migrations/migrate-down.sh`. |
| Mocked migration runner tests | Pass | `scripts/migrations/tests/migrate-up-test.sh`, `migrate-up-atomic-test.sh`, and `migrate-down-test.sh` passed when run individually with bounded execution. These tests do not execute SQL on PostgreSQL. |
| Go focused tests | Blocked | `GOPROXY=off GOSUMDB=off go test ...` failed before compilation because dependencies such as pgx, chi, zap, uuid, and kafka-go are not cached and offline lookup is disabled. This is not a code-test failure or pass. |
| Flutter consumer/driver | Blocked | `flutter` and `dart` are unavailable. |
| Docker/Compose, Helm, kubectl, PostgreSQL CLI/server | Blocked | Commands are not installed; no live migration, broker, Compose, or chart validation possible. |
| Admin clean build in this extracted archive | Not rerun / blocked by environment state | `node_modules` are not included in this archive. Earlier archive-specific admin build evidence is historical and does not substitute for a clean-checkout install/build. |

## Prioritized Phase 0 gaps and acceptance criteria

1. **Runtime reachability:** Trace all gateway upstreams, registered routes, background workers, and actual deployment manifests. Acceptance: every claimed production route has an identified active handler/upstream and auth policy, or is explicitly marked stale/unimplemented.
2. **Product coverage:** Complete the five-product capability matrix with source evidence and explicit implemented/partial/missing status. Acceptance: no product is called implemented solely because an entity, route, schema, or folder exists.
3. **API/client contract trace:** Enumerate route method/path, handler, middleware, payload schema, status/error behavior, and Flutter/admin consumer. Acceptance: no known route is omitted; unresolved consumers are called out.
4. **Data ownership:** Trace all SQL reads/writes and constraints to domain owners. Acceptance: every business table has a proposed owner with evidence, cross-domain reads/writes are listed, and disputed owners are explicitly unresolved pending review.
5. **Security baseline:** Map authentication, authorization, tenant context, ownership checks, webhook verification, rate limits, and sensitive logging. Acceptance: each exposed route has a documented policy and test gap.
6. **Reproducible builds:** Run Go unit tests and Flutter/admin builds from clean dependency installs. Acceptance: results and toolchain versions are recorded; unavailable external resources remain explicit blockers.
7. **Deployment baseline:** Select canonical local and production deployment paths and validate Compose/Helm/Kubernetes in a tool-enabled environment. Acceptance: one documented supported path works; secondary manifests are classified as supported, legacy, or unverified.
8. **Migration baseline:** Run all eligible migrations on an empty PostgreSQL instance and a representative upgrade snapshot. Acceptance: deterministic order, correct checksums/ledger rows, safe retry, and reviewed 015/016 compatibility are evidenced.

## Decision

The previous `phase-0-acceptance-review.md` permitted reversible Phase 1 work despite blockers. Under the user's master roadmap, that is a **limited planning authorization, not full Phase 0 acceptance**. Phase 0 remains open until the acceptance items above are either verified or formally accepted as environment-dependent blockers with a reproducible external validation procedure. No Phase 3–7 work should be represented as accepted before prerequisite gates pass.

### Latest continuation — Nidus route/security trace

The endpoint trace now includes a route-family matrix for the Nidus Chi router, distinguishing public routes, JWT-protected groups, dependency/feature-flagged routes, token-authorized split-fare acceptance, and WebSocket subscription authorization. It also records global router middleware and distinguishes middleware registration from handler-level resource authorization. This is additional static evidence only: Phase 0 remains open until route registry comparison, contract/security tests, Kong parsing, and live request-path validation are completed.


## Latest continuation — Deployment-specific gateway identity comparison

A source comparison across Compose development, Compose production, Kubernetes Service definitions, and Kong config refined the prior upstream finding. The Compose overlays define the backend under service key `backend` with environment-specific container names, while Kong targets `nidaw-backend:8080`; no matching Compose alias was found in the inspected files. Kubernetes does define a Service named `nidaw-backend`, but its Service port is `80` with `targetPort: 8080`, so `nidaw-backend:8080` is not the Service's declared port. This is a confirmed static inconsistency across deployment modes, not proof of a live outage: uninspected overlays or alternate networking may exist.

The gateway also duplicates route declarations between `kong.yml` and `platform/gateway/routes/*.yaml`, while the Compose overlays mount only `kong.yml`. The repository does not evidence an automatic include/merge step for the fragments. The service path prefixes combined with `strip_path: false` are flagged as a suspected URI-composition defect pending parse/runtime verification.

**Status remains open:** Docker/Kong tooling and live deployment services are unavailable in this environment. No runtime reachability claim is made. See `endpoint-client-contract-trace.md` for the deployment matrix and required validation sequence.


### Client/router/Kong method-path discrepancy pass

Static review now records candidate mismatches between client paths (`/api/v1/rides/*`, `/api/v1/nidus/rides/active`, `/api/v1/nidus/safety`, and driver pre-selfie redemption), the explicit Nidus router registrations, and Kong method/path coverage. These remain candidates where another mounted router or rewrite could provide compatibility; no runtime alias is assumed. Haven/Vorax gateway routes are not proof of mounted product routers. See `endpoint-client-contract-trace.md` for evidence and remediation. Phase 0 remains open pending a complete generated route registry and contract/integration verification.


### Latest continuation — fail-closed product module gate

The backend CI product gate was changed so missing Haven/Vorax Go modules are a blocking finding rather than an informational line after a successful import-only scan. The step is ordered after Go tests and coverage upload and uses `if: always()` so the architecture finding remains visible even if tests fail. The current expected gate result is non-zero until real product implementations or an evidence-backed alternate-runtime decision are reviewed. Empty placeholder packages are explicitly rejected.
