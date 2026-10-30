# NIDAW Repository Discovery and Baseline Audit

## Status

- Phase: 0 — Repository Discovery and Baseline.
- Evidence source: uploaded `N-main.zip`, inspected statically.
- Archive integrity: passed ZIP integrity test.
- Audit limitation: no deployed environment, production database, production traffic, credentials, or secret manager was inspected.
- Phase 0 acceptance is recorded in `phase-0-acceptance-review.md`, with environment-dependent verification blockers explicitly carried forward. This permits reversible Phase 1 path migration but is not production certification.

## Verified repository inventory

Current archive root: `N-main/`. The archive includes `services/api/` (Go), `apps/consumer_app/` (Flutter consumer app), `apps/driver_app/` (Flutter driver app), `apps/admin_console/` (React/TypeScript/Vite), `data/migrations/`, `platform/gateway/` (Kong), `platform/docker/`, `platform/kubernetes/`, `platform/helm/`, `infrastructure/` (Terraform), `platform/monitoring/`, `analytics/`, `ml/`, `docs/`, `scripts/`, `tests/`, `legal/`, `security/`, and GitHub Actions workflows. The primary backend/client applications, platform assets, and SQL data assets have been moved to their approved destinations; deployment-path validation is ongoing.

Backend module directories verified under `services/api/internal/modules/`: `analytics`, `auth`, `autonomous`, `chat`, `corpus`, `driver-onboarding`, `identity`, `ledger`, `legal`, `logix`, `nidus`, `notifications`, `payment`, `payments`, `pricing`, `promotions`, `selfie`, `telephony`. Both `payment/` and `payments/` exist; their ownership and overlap need tracing before consolidation.

`services/api/cmd/server/main.go` is a large composition root that initializes configuration, PostgreSQL, Kafka, auth, Nidus services, Redis, optional ledger components, HTTP middleware, and module routers. The Go module is named `nidaw-backend` and declares Go 1.19.

## Five-product capability matrix

| Product | Verified source evidence | Initial classification | Outstanding verification |
|---|---|---|---|
| **Nidus** | Substantial `services/api/internal/modules/nidus/` domain/application/infrastructure/HTTP code: ride and driver entities, dispatch, matching, pricing, ETA, location cache, WebSocket handlers, lifecycle and tests. Kong route exists at `platform/gateway/routes/nidus.yaml`. | Implemented in part; strong backend footprint. | Validate state transitions, payment effects, authorization, DB constraints, race behavior, API consumers, and test results. |
| **Haven** | `platform/gateway/routes/haven.yaml`; hotel analytics schemas and `stg_hotels.sql`. No `services/api/internal/modules/haven/` directory in module inventory. | References exist; complete reservation implementation not established. | Trace route upstream, handlers, tables, inventory/availability, reservations, provider workflow and client use. |
| **Vorax** | `platform/gateway/routes/vorax.yaml`; order analytics schema and `stg_orders.sql`. No `services/api/internal/modules/vorax/` directory in module inventory. | References exist; complete food-order implementation not established. | Trace route upstream, merchant/menu/order/delivery lifecycle, persistence, payment/refunds and clients. |
| **Logix** | `services/api/internal/modules/logix/` includes shipment entity and services for customs, errors and load matching; `main.go` does not import or mount Logix. | Partial source footprint; runtime reachability not demonstrated. | Verify persistence, routes, IDs, documents, carrier integration, lifecycle, billing and tests; identify any alternate active runtime. |
| **Corpus** | `services/api/internal/modules/corpus/` includes corporate account entity and `create_booking` application command; `main.go` does not import or mount Corpus. | Partial source footprint; runtime reachability not demonstrated. | Verify tenant/org model, policy decisions, approvals, orchestration, adapters, persistence, routes and audit; identify any alternate active runtime. |

A route or analytics schema does not prove a complete product implementation. Absence of a product-named module does not prove no related logic exists elsewhere; further tracing is required.

## Shared capabilities and integration evidence

- Auth: `services/api/internal/modules/auth/`, `identity/`, and `services/api/internal/shared/auth/`.
- Payments: both `services/api/internal/modules/payment/` and `payments/`, plus shared Chapa, M-Pesa and Telebirr gateway adapters.
- Ledger/finance: `services/api/internal/modules/ledger/` with domain, application, repository, adapter, HTTP and test code.
- Notifications: `services/api/internal/modules/notifications/` and `services/api/internal/shared/integrations/notifications/`.
- Promotions and pricing: `services/api/internal/modules/promotions/`, `pricing/`, and Nidus-specific pricing services.
- Event infrastructure: `services/api/internal/shared/eventbus/` includes Kafka and in-memory bus implementations.
- Persistence/cache: shared PostgreSQL and Redis infrastructure under `services/api/internal/shared/`.
- API specification: `services/api/api/openapi.yaml`; Kong routes for Nidus, Haven and Vorax.
- Infrastructure includes Docker Compose, Kubernetes, Helm, Terraform and monitoring. The active canonical deployment path is not yet established.

## Database and migrations

PostgreSQL migrations are present under `data/migrations/postgres/` from `001_initial_schema.sql` through `017_t5_fault_injection.sql`, plus `data/migrations/timescale/001_hypertables.sql` and seed files. A table-owner map is **not yet verified**. Next: extract table DDL, migration ordering/dependencies, repository SQL and ownership for every business table. Do not infer ownership from migration filenames alone.

## Baseline checks and observed results

| Check | Result | Notes |
|---|---|---|
| ZIP integrity | Passed | `ZipFile.testzip()` returned no corrupt member. |
| Admin build before/after core app move | **Passed** | `npm --prefix apps/admin_console run build` completed using the dependency tree included in the original archive; generated outputs were removed afterward. Generated `apps/admin_console/dist/` should not be committed unless deployment explicitly requires it. |
| Go toolchain | Available | Environment: Go 1.23.2; module declares Go 1.19. Align CI/toolchain deliberately rather than blindly upgrading. |
| Go tests | **Blocked / inconclusive** | `cd services/api && go test ./...` attempted dependency downloads and exceeded the execution time limit before tests ran. This is neither a pass nor a test failure. Retry with cached dependencies or network access. |
| Flutter toolchain | **Unavailable** | `flutter --version` returned `command not found`; consumer and driver build/tests could not run. |
| Lint, DB integration, E2E | Not run | Require additional focused checks and possibly Docker, database, credentials or external services. |

## Confirmed developer-workflow issues

- Root Makefile test targets now use `services/api`, `apps/consumer_app`, and `apps/driver_app`.
- Root README now recommends `make dev`, which explicitly selects `platform/docker/compose/base.yaml` and `platform/docker/compose/dev.yaml`.
- `make clean` now stops the local Compose stack without deleting volumes; infrastructure teardown is separated into an explicit `destroy-infra` target.
- Generated admin `node_modules`, `dist`, and TypeScript build-info output were removed from the working copy; package lockfiles are retained and generated paths are ignored.

## Initial risk register

| Finding | Evidence | Impact | Recommended action |
|---|---|---|---|
| Layout diverges from target | `services/api/`, `apps/consumer_app/`, `apps/driver_app/`, `platform/gateway/`, `database/` | Path migration requires coordinated import, CI, container, and deployment updates; core application moves are now in progress. |
| Payment module ambiguity | `payment/` and `payments/` both exist | Potential duplicate concepts and unclear ownership | Trace models, routes, tables and consumers before merging/renaming. |
| Haven/Vorax modules not found | Gateway and analytics references exist, but no matching module dirs | Risk of treating route/schema references as production workflows | Trace route targets and all handler/DB/client paths. |
| Corpus/Logix appear partial | Limited verified module footprints | Required workflows may be missing | Trace runtime entry points, persistence, tests and contracts. |
| Main composition root is broad | `services/api/cmd/server/main.go` wires many modules and infrastructure | Dependencies harder to audit and modules harder to isolate | Map current wiring, then refactor incrementally after baseline. |
| Test baseline incomplete | Go downloads timed out; Flutter absent | Cannot claim full repository buildability | Retry Go tests with dependencies available and run Flutter checks in a Flutter-enabled environment. |
| Destructive cleanup command | Makefile `clean` includes volume removal and Terraform destroy | Potential data/infrastructure loss | Separate safe cleanup from explicitly destructive teardown. |
| Multiple deployment mechanisms | Compose, Kubernetes, Helm, Terraform and workflows exist | Drift and ambiguous operational path | Identify supported deployment target and test it. |

## Assumptions not treated as facts

README claims about CQRS/event sourcing, Kafka, TimescaleDB, Feast, MLflow and TorchServe are not proof that every capability is operational. Existing tests are not assumed to pass. No production database, live environment, or real credentials were inspected.

## Additional Phase 0 findings (deeper static scan)

- Cross-module import scan identified candidate boundary violations: `chat -> nidus`, `ledger -> nidus`, `nidus -> ledger`, `nidus -> payments`, and `nidus -> promotions`. The counts and recommended direction are in `domain-dependency-findings.md`. Composition-root imports from `cmd/server` are expected and should remain explicit.
- The Corpus create-booking command directly reads corporate employee/policy records and inserts `corporate_bookings`, then publishes an event and may publish a downstream approval event. The observed publication result is not checked in the inspected code path, and the DB write plus event publication are not shown as one transaction. This is a concrete reliability risk to verify and address in Phase 4/7, not proof of a runtime failure.
- Kong configuration defines `haven-service` and `vorax-service` and routes exist, but no corresponding Go modules are present in the scanned module directory. The active upstream implementation and deployment must be confirmed before treating those products as operational.
- The migration inventory shows overlapping definitions/alterations of `transactions` in migrations 015 and 016. Their clean-install and upgrade compatibility must be tested before migration changes. Migration 017 creates `t5_fault_injection`; verify strict test-environment gating and permissions.
- Root `Makefile` and `scripts/deploy.sh` refer to `driver-app` while the real folder is `driver_app`. Root `Makefile clean` invokes destructive volume removal and Terraform destruction, so routine cleanup must be separated from explicit destructive teardown.

## Phase 0 acceptance

**Accepted for reversible Phase 1 migration with explicit verification blockers.** Inventory, five-product matrix, preliminary risk list, static import graph, preliminary table ownership, endpoint-to-client trace, and API/event integration inventories are documented. Full route-to-handler authorization tests, SQL read/write ownership, migration execution, tenant-isolation tests, active deployment-path validation, and reproducible Go/Flutter baselines remain outstanding. This acceptance does not certify production readiness.

### Runtime reachability correction

A focused read of `services/api/cmd/server/main.go` confirms that Corpus and Logix are not imported or mounted by the current executable composition root. The `payment` transaction-processing HTTP handler is also not mounted there, while `payments` is used for payment-method registry wiring. This strengthens the classification: Corpus and Logix have source footprints but their expected product workflows are not shown as reachable through the current Go server. Haven and Vorax still require external-upstream verification because Kong defines their upstream names while matching Go modules are absent.


## Current-source revalidation (master-roadmap reconciliation)

See `phase-0-current-source-validation.md` for the current archive recheck. This updates stale migration inventory through `018_ledger_event_outbox.sql`, records the actual module/runtime reachability evidence, and distinguishes mocked migration-script tests from real PostgreSQL validation. Phase 0 remains open; prior limited planning authorization is not full acceptance.
