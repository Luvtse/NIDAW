# NIDAW Implementation Checklist

## Phase 0 — Repository discovery and baseline

- [x] Identify archive root and major technology/application directories.
- [x] Inventory Go modules and identify missing product-named backend modules.
- [x] Record initial admin build result from prior baseline run.
- [x] Attempt Go test baseline; result is blocked because dependencies are not cached and dependency retrieval is unavailable/timed out.
- [x] Record Flutter verification blocker (Flutter SDK unavailable in the environment).
- [x] Record path inconsistencies in root Makefile and deploy script (`driver-app` vs actual `driver_app`).
- [x] Create preliminary product capability matrix and risk register.
- [x] Scan cross-module Go import edges and document candidate boundary violations.
- [x] Inventory migration files and create preliminary database ownership map.
- [x] Inventory API/gateway/event integration evidence and gaps.
- [x] Confirm runtime reachability for key modules from the current composition root: Corpus and Logix are not imported/mounted; transaction-processing `payment` HTTP handlers are not mounted there.
- [x] Trace key registered routes to handlers and middleware in `route-security-database-trace.md`; full endpoint-to-client consumer matrix remains outstanding.
- [x] Review migration files 015/016 and identify overlapping `transactions` definitions; generate a conservative static table-to-migration/module-reference inventory in `schema-ownership-inventory.md`. Full authoritative ownership approval and PostgreSQL-backed validation remain outstanding.
- [x] Make migration SQL and its `schema_migrations` ledger row commit atomically; add a mocked-psql regression test. Real PostgreSQL execution remains outstanding.
- [x] Review security middleware and tenant-context evidence; route-by-route authorization and tenant-isolation tests remain outstanding.
- [ ] Establish reproducible Go and Flutter test baselines in a dependency-enabled environment (external blocker documented).
- [x] Perform static Compose/Kong/Kubernetes deployment-path validation and YAML syntax parsing; findings and evidence recorded in `phase-0-deployment-path-validation.md`. Runtime validation remains open because Docker, Helm, and kubectl are unavailable.
- [ ] Confirm canonical active deployment path and validate Compose/Kubernetes/Helm references at runtime; DNS, selectors, Kong upstream URI, and metrics listener remain unverified in a live environment.
- [x] Limited Phase 0 planning review recorded in `phase-0-acceptance-review.md`; it authorized reversible Phase 1 work but does not satisfy full Phase 0 acceptance under the master roadmap.
- [ ] Phase 0 current-source recheck: see `phase-0-current-source-validation.md`; full clean-checkout, live database, client-contract, security-route, and deployment validation gates remain open.

**Gate:** Phase 0 is still open under the master roadmap. The earlier review was a limited planning authorization, not full acceptance. Phase 1 directory moves already exist and must be validated; do not advance the roadmap based on those moves alone.

## Phase 1 — Canonical repository structure

- [x] Phase 1 started after the documented Phase 0 acceptance review.

## Master roadmap reconciliation (authoritative phase numbering)

The user's `NIDAW — MASTER IMPLEMENTATION PROMPT AND EXECUTION ROADMAP` is the authoritative phase definition. Earlier progress notes used inconsistent phase numbers for payment/outbox work. Those labels are corrected below; existing code is not proof that a phase acceptance gate passed.

- [ ] **Phase 0 — Repository discovery and baseline:** preliminary evidence exists, but clean-checkout Go/Flutter baselines, full client-contract trace, live migration validation, and deployment-path verification remain open. See `phase-0-acceptance-review.md` for the limited acceptance recorded for reversible work; this is not full Phase 0 completion.
- [ ] **Phase 1 — Canonical repository structure:** major directory moves are present, but canonical `packages/api-contracts`, `packages/event-contracts`, and `packages/shared-config` are absent, and clean-checkout/native build plus deployment validation remain open.
- [ ] **Phase 2 — Build reproducibility and developer workflow:** outstanding; no clean-checkout acceptance evidence.
- [ ] **Phase 3 — DDD and module boundaries:** static Go import check exists, but full domain ownership, cross-domain read/write audit, cycles, and all five product boundary enforcement are not accepted.
- [x] Harden the product-module CI guard so missing required Go product modules fail closed instead of producing a green import-only result; see `phase-0-product-module-gate-hardening-2026-10-23.md`. Current gate intentionally fails because Haven and Vorax module directories are absent; do not satisfy it with empty placeholders.
- [ ] **Phase 4 — Product workflow and domain integrity:** outstanding as a five-product acceptance gate.
- [ ] **Phase 5 — Database ownership and migration safety:** partial migration guardrails exist; PostgreSQL-backed empty-database/upgrade validation, ownership approval, and 015/016 resolution remain open.
- [ ] **Phase 6 — API contracts and cross-product integration:** outstanding. The current repository does not yet demonstrate a complete versioned API/event contract catalogue, provider/consumer validation, and acceptance across all five products.
- [ ] **Phase 7 — Domain events, reliable messaging, and transactional outbox:** implementation slice exists for the ledger outbox, but it is **premature/partial relative to the master roadmap** because Phases 3–6 are not accepted. Live PostgreSQL/Kafka validation, full event-path coverage, crash-after-ack duplicate delivery, consumer idempotency, and outbox metrics remain open.
- [ ] **Phase 8 — Modular-monolith runtime and application composition:** outstanding as a complete gate; outbox worker wiring alone does not satisfy this phase.
- [ ] **Phase 9 — Gateway, security, tenancy, and configuration:** partial static audit only; route-by-route authorization and tenant-isolation tests remain open.
- [ ] **Phase 10 — Product applications and contract alignment:** outstanding as a cross-client/product gate; one admin build does not prove all client workflows.
- [ ] **Phase 11 — Observability and operational resilience:** partial shared metrics/logging exist, but outbox metrics and critical workflow recovery/runbooks remain open.
- [ ] **Phase 12 — Testing strategy for all five products:** outstanding; broad unit, integration, contract, end-to-end, and architecture acceptance has not been demonstrated.
- [ ] **Phase 13 — CI/CD, containers, and deployment:** static updates exist; Docker/Compose/Helm/Kubernetes runtime verification remains open.
- [ ] **Phase 14 — Service-extraction readiness:** outstanding; no extraction should occur before evidence-based assessment.
- [ ] **Phase 15 — Documentation and handover:** partial docs exist; final evidence-based handover is not yet appropriate.
- [x] Re-run admin console production build from the archived repository (`npm --prefix apps/admin_console run build`): TypeScript and Vite build passed.
- [x] Check migration script shell syntax (`bash -n`): both up/down scripts passed syntax parsing.
- [x] Trace Makefile, setup/deploy scripts, CI workflows, and actual Compose paths; document competing deployment assumptions.
- [x] Inspect migration runner bookkeeping, pending-selection, target-version, checksum, and seed-data behavior; document concrete risks.
- [ ] Finish migration-runner audit: checksum drift detection and PostgreSQL-backed validation of the overlapping 015/016 migration sequence remain outstanding; do not alter applied migration history casually.
- [ ] Choose the canonical local/deployment workflow and validate Compose, migration execution, and manifests in an environment with Docker/PostgreSQL/Helm tooling.
- [x] Compare migration 015/016 comments against their actual statements and runner order; document the prerequisite contradiction and nested transaction-control risk.

- [x] Add static endpoint-to-client trace in `endpoint-client-contract-trace.md`; dynamic paths and runtime contract validation remain outstanding.
- [x] Continue Phase 0 deployment-path static audit: identify Compose/Kong upstream hostname mismatch, Kubernetes Service selector mismatch, Kong service/route prefix duplication risk, and metrics-port annotation discrepancy; document exact evidence and runtime acceptance actions in `phase-0-deployment-path-validation.md`.

- [x] Phase 1: moved Go backend and three client applications to canonical primary destinations; updated path references in workflows, Compose, scripts, editor config, and docs. Admin production build passed after the move using archived dependencies.
- [x] Phase 1: move platform directories to `platform/{gateway,docker,kubernetes,helm,monitoring}` and SQL assets to `data/{migrations,seeds}`; update references and run static path checks. Runtime Compose/Kubernetes/Helm validation remains blocked by missing local CLIs.
- [ ] Phase 1: run clean-checkout builds/tests and Compose validation in a dependency-enabled environment.
- [x] Phase 1: post-move admin build passed; shell syntax and selected YAML parse checks passed; stale primary app-path scan passed.
- [x] Phase 1: repair identified Compose bind-mount paths, add the Feast Dockerfile, and reconcile deployment script paths with the actual Terraform and Helm layout.
- [x] Phase 1: add production Dockerfiles for the Go API and consumer web app; static path checks pass.
- [x] Phase 1: add staging Helm values, align template keys, and remove the duplicate backend-only staging deployment workflow.
- [x] Phase 1: test migration selection with a mocked `psql`: staging skips test-only fault injection, production skips seed/fault-injection migrations, and `--target` acts as an upper bound.
- [ ] Phase 1: validate Docker builds, Compose startup, Helm rendering, and staging migration execution in a dependency-enabled environment.


## Phase 3 — Migration and boundary guardrails (checkpoint)

- [x] Harden migration runner dry-run, target validation, environment exclusions, and checksum drift detection.
- [x] Add mocked-database migration runner and rollback safety tests and include them in backend CI.
- [x] Add a CI guard against direct Go imports between the five product modules.
- [x] Report product module directories that are absent without claiming implementation.
- [ ] Execute PostgreSQL migration tests from an empty database and a representative existing schema.
- [ ] Validate migration failure/retry behavior and the ledger record under real database failures.
- [ ] Complete SQL read/write ownership and route/event boundary audit.

## Phase 4 — Migration atomicity and schema evidence

- [x] Apply migration SQL and the ledger insert in a single transaction without editing checked-in historical migrations.
- [x] Add a regression test proving transaction markers are normalized and ledger SQL is part of the same `psql --single-transaction` invocation.
- [x] Generate a static schema/table-to-migration/module-reference inventory with explicit caveats.
- [ ] Execute all migrations against a clean PostgreSQL 15 database and a representative upgrade snapshot.
- [ ] Resolve and review the 015/016 payment schema overlap before any historical migration consolidation.
- [ ] Validate real database failure/retry behavior and recovery procedures.

- [ ] Payment-workflow hardening slice: payment idempotency, refund integrity, provider reconciliation, and durable event delivery validated against PostgreSQL. This is a workstream, not a substitute for master Phase 5 database ownership/migration acceptance.
- [x] **Phase 7 implementation slice (not phase acceptance):** add first-slice ledger event outbox migration, transaction-aware publisher, retrying dispatcher, startup wiring, and publisher unit tests. This work was previously mislabeled Phase 6; see `phase-roadmap-reconciliation.md`.
- [ ] **Phase 7 acceptance:** trace every active top-up/payout/webhook/escrow event path; run Go tests and PostgreSQL/Kafka integration tests, including rollback, retries, duplicate delivery, and concurrent dispatchers.
- [x] **Phase 7 test artifacts (not executed):** add environment-gated PostgreSQL integration tests for outbox rollback atomicity, concurrent dispatchers, and broker retry behavior.
- [ ] **Phase 7 acceptance:** execute the outbox integration tests against dedicated PostgreSQL and Kafka; add crash-after-ack duplicate-delivery coverage and outbox metrics.

### Phase 0 follow-up — gateway reachability delta

- [x] Statically compared Kong upstream targets with Compose service names and traced the main Go server entry point.
- [x] Documented the Kong upstream DNS inconsistency (`nidaw-backend:8080` vs Compose service key `backend`) and possible service-path/route-path duplication.
- [x] Documented that Nginx `/health` and `/ready` are proxy-local static responses, not backend readiness checks.
- [ ] Validate Kong config with the actual Kong image/version and run an integration request that confirms upstream host and URI.
- [ ] Confirm which ingress and deployment manifest is authoritative for each environment.
- [ ] Complete the mounted-route → middleware/auth policy → handler → client method/path trace for all products and shared capabilities.

These findings improve the Phase 0 evidence baseline; they do not close Phase 0 or authorize dependent phases.


- [x] Phase 0 client/router coverage delta (2026-10-22): documented driver lifecycle path mismatches, absent explicit active-ride routes, missing safety route registration, broad `/api/v1/drivers/*` coverage gap, analytics event route uncertainty, and feature-gated ledger/selfie behavior in `phase-0-client-router-coverage-delta-2026-10-22.md`.
- [x] Phase 0 API contract-spec coverage audit (2026-10-22): `services/api/api/openapi.yaml` declares only four paths while mounted modules and client references cover broader route families; documented confirmed mount/security/feature-gate evidence in `phase-0-api-contract-coverage-2026-10-22.md`.
- [ ] Complete method/path/request/response/auth/feature-flag matrix for consumer, driver, and admin clients and reconcile it with OpenAPI and the mounted router.
- [ ] Agree and test canonical client/server contracts for active ride, driver lifecycle/profile/earnings/documents/location, safety, and analytics before changing API paths or exposing unsupported workflows.
- [ ] Run Go tests after dependency availability; prior targeted test command timed out while downloading dependencies and is not a pass.

### Phase 0 continuation note — route/security trace

- [x] Add static Nidus route-family mapping for auth middleware, conditional mounting, public endpoints, split-fare token authorization, and WebSocket subscription authorization.
- [x] Record gateway coverage gaps and the distinction between global middleware and resource-level authorization.
- [ ] Generate a complete method/path registry from the running Chi router and compare it against Kong routes and client usage.
- [ ] Run route-level ownership/role tests and validate Kong URI forwarding in a tool-enabled runtime.
- [ ] Keep Phase 0 open until acceptance evidence is complete or remaining external blockers have explicit reproducible validation procedures.


### Phase 0 continuation — deployment-specific Kong reconciliation

- [x] Compared Kong upstream identity with Compose development and production service names and the Kubernetes Service definition.
- [x] Distinguished static configuration mismatch from unverified runtime behavior.
- [x] Recorded duplicate gateway route sources and the unverified service-path/route-path composition.
- [ ] Select the canonical deployment mode and validate Kong configuration with the matching Kong toolchain.
- [ ] Validate DNS, connectivity, forwarded URI, and representative authenticated/public requests against a running backend.
- [ ] Generate complete method/path coverage from the mounted Go router and compare against the effective Kong configuration and client calls.

This source-only comparison corrects the earlier generalized hostname note; it does not close Phase 0.

- Phase 0 route/client/gateway discrepancy pass added: shorter legacy ride paths, `/nidus/rides/active`, `/nidus/safety`, pre-selfie redemption, GET estimates, lifecycle gateway coverage, and driver-location read coverage require full mounted-router and runtime confirmation. These are documented as candidates, not silently “fixed.”

### Phase 0 continuation — active-ride endpoint contract trace

- [x] Trace consumer and driver active-ride client calls against the Nidus router and existing handler.
- [x] Confirmed the driver-specific `GetActiveRide` handler exists but is not mounted in the inspected router; its query error mapping also conflates database failures with no active ride.
- [x] Document safe canonical routes, rider/driver authorization semantics, status selection, and required contract tests in `phase-0-active-ride-contract-trace.md`.
- [ ] Implement and test the agreed active-ride API contract; Phase 0 remains open.

### Phase 0 continuation — confirmed client/API contract findings

- [x] Verify active-ride path mismatch against the concrete Chi router and `GetRide` UUID parsing behavior.
- [x] Verify driver legacy lifecycle paths against registered Nidus paths.
- [x] Confirm safety client repository path has no matching route group in the inspected active composition root.
- [x] Confirm pre-selfie upload route exists conditionally and the multipart field differs (`selfie` client vs `image` server).
- [ ] Agree canonical active-ride and driver lifecycle API contracts before coordinated client/server changes.
- [ ] Fix multipart field compatibility with handler and client tests.
- [ ] Implement or explicitly disable safety workflows until real handlers, authorization, and persistence are present.
- [ ] Run route-level tests and client tests with dependencies available; validate the selected gateway path against a running backend.

These are static source findings; Phase 0 remains open until the full acceptance gate is satisfied.

- [x] Correct consumer pre-selfie multipart key from `selfie` to canonical server field `image` in `apps/consumer_app/lib/features/nidus/data/repositories/pre_selfie_repository.dart`; Flutter contract test and end-to-end upload validation remain pending.
- [ ] Phase 0 continuation (2026-10-22): active-ride client/router mismatches and deployment host/port/URI findings documented in `phase-0-continuation-2026-10-22.md`; runtime Kong/Compose/Kubernetes validation remains outstanding.

- [x] Phase 0 client endpoint literal inventory (2026-10-22): added a line-level CSV across consumer, driver, and admin source references; documented confirmed driver path, active-ride, driver capability, safety, analytics, and pre-selfie contract findings. Corrected stale pre-selfie multipart documentation (`selfie` → `image`); contract tests and full dynamic/admin route resolution remain open.
- [ ] Resolve all client paths and methods, including admin base-plus-relative paths, then compare against the mounted route registry and OpenAPI before making coordinated API changes.


### Phase 0 continuation — static mounted-route registry (2026-10-22)

- [x] Build source-derived method/path registry for auth, legal/consent, Nidus, notifications, chat, telephony, selfie, ledger, metrics, and health routes; record visible middleware and mount conditions in `phase-0-mounted-route-registry-static-2026-10-22.csv`.
- [x] Document static-vs-runtime limitations, security layers, feature-gated composition, and client-contract gaps in `phase-0-mounted-route-registry-static-2026-10-22.md`.
- [x] Confirm exact public payment webhook path `POST /api/v1/payments/webhooks/{provider}` and signature-verification gate from `WebhookHandler.Register`.
- [ ] Resolve the source/comment contradiction for WebSocket middleware placement; test authenticated and unauthenticated handshakes.
- [ ] Compare registry against a runtime Chi route walk, Kong effective paths, OpenAPI, and all client calls.
- [ ] Add and execute route-level authorization and feature-flag tests in a dependency-enabled environment.

Static source evidence only; Phase 0 acceptance remains open.

- [ ] Go route/ledger tests attempted but blocked: dependency downloads did not complete within the 90-second command limit; rerun in a dependency-enabled environment.

### Phase 0 continuation — route security and active-ride error semantics (2026-10-22)

- [x] Correct the WebSocket route comment to match the actual protected route-group composition; no runtime behavior changed.
- [x] Correct active-ride handler query error mapping so database failures are not reported as missing profiles/active rides.
- [ ] Add and execute PostgreSQL-backed regression tests for active-ride no-row versus database-failure cases.
- [ ] Add and execute mounted-router WebSocket handshake tests for missing, invalid, and valid access tokens.
- [ ] Agree separate canonical consumer and driver active-ride contracts before mounting aliases or changing client paths.
- [ ] Re-run Go tests in a dependency-enabled environment; current attempt is blocked by unavailable module downloads.

This is a narrow source correction, not Phase 0 acceptance.

### Phase 0 continuation — migration runner regression (2026-10-22)

- [x] Add a regression test exercising the real 015/016 payment migration files through the runner's transaction-control normalization using mocked `psql`.
- [x] Run all four migration shell tests; all passed, including rollback safety, atomic ledger bookkeeping, runner environment/checksum/target checks, and real-file wrapper normalization.
- [x] Run Bash syntax checks on migration up/down scripts and all migration shell tests.
- [ ] Execute 015/016 against a real disposable PostgreSQL database on an empty schema and representative upgrade states; compare final schema objects and constraints.
- [ ] Validate unique-index creation against production-like duplicate data and confirm backup/restore and rollback recovery procedures.

Mocked migration tests do not satisfy the PostgreSQL-backed Phase 0 acceptance gate.

### Phase 0 continuation — payment-integrity migration preflight (2026-10-22)

- [x] Add a read-only preflight for duplicate transaction idempotency keys, invalid refund totals, non-positive charge amounts, and duplicate pending refunds before applying payment-integrity migrations 015/016.
- [x] Add and pass a shell regression test verifying expected checks, no schema/data mutation statements, and propagation of `psql` failures.
- [x] Re-run all four existing migration shell tests; all passed alongside the new preflight test.
- [ ] Run the preflight and migrations against a disposable PostgreSQL instance, including an empty schema and representative upgrade fixtures.
- [ ] Verify behavior with intentionally duplicated idempotency keys and invalid legacy refund totals, then document a reviewed remediation procedure.

The preflight SQL has not been executed against PostgreSQL in this environment. Phase 0 remains open.

### Phase 0 continuation — Kong and mounted-route reconciliation (2026-10-22)

- [x] Compare the 24 Kong Route objects with the 79-record static Go mounted-route registry; document candidate mismatches and caveats in `phase-0-kong-mounted-route-reconciliation-2026-10-22.md`.
- [x] Flag Kong Haven/Vorax route families without corresponding route records in the current active-composition registry, the Nidus ride-detail ID-pattern discrepancy, and `/ws` versus `/api/v1/ws` path discrepancy.
- [ ] Approve a route-by-route public/internal/feature-gated exposure matrix and reconcile all 65 records not matched by the conservative static comparison.
- [ ] Validate Kong schema/rendering and exact upstream URI in the canonical runtime topology; test representative authentication, missing-route, and upstream-failure cases.

This is a static review queue, not a claim that all unmatched mounted routes are broken. Phase 0 remains open.

### Phase 0 continuation — route exposure review matrix (2026-10-22)

- [x] Add a reproducible static review matrix for all 79 source-derived mounted method/path records, preserving owner, observed auth scope, mount condition, and direct Kong candidate routes.
- [x] Add a generator and regression check; all matrix rows remain explicitly `UNREVIEWED` and the artifact labels itself as static-only.
- [ ] Obtain owner decisions for every route: public-through-gateway, internal-only, feature-gated, or unsupported in the canonical deployment.
- [ ] Validate the reviewed matrix against rendered Kong configuration and runtime upstream URI/authorization tests.

The current conservative exact/regex pass finds 12 direct Kong candidates and 67 records without a direct candidate. These counts use different matching logic from the earlier 65-record review queue and are not runtime coverage claims. Phase 0 remains open.

### Phase 0 continuation — driver WebSocket endpoint configuration (2026-10-22)

- [x] Confirmed the driver Docker build passes `WS_BASE_URL`, while driver dependency injection previously read `API_BASE_URL` instead.
- [x] Standardized driver configuration on the complete `WS_BASE_URL` endpoint (including `/ws`) and preserved the driver role query plus subprotocol-based JWT authentication.
- [x] Added and passed `scripts/tests/driver-websocket-config-test.sh`.
- [ ] Run Flutter analysis/tests and authenticated/unauthenticated WebSocket handshake tests through the selected gateway topology.

This is a client configuration correction with static regression coverage; it does not establish gateway or handshake runtime correctness. Phase 0 remains open.

### Phase 0 continuation — Kong upstream URI correction (2026-10-22)

- [x] Remove duplicate service path prefixes from Nidus, Haven, Vorax, and auth services whose routes already contain full `/api/v1/...` paths.
- [x] Preserve the public `/ws` route while explicitly mapping it to the backend-mounted `/api/v1/ws` path using route stripping and a service path.
- [x] Add a static YAML/path-contract regression test and record the correction in `phase-0-kong-upstream-path-correction-2026-10-22.md`.
- [ ] Validate the declarative configuration with the pinned Kong image/version and confirm forwarded URIs against a running backend.
- [ ] Resolve the canonical Compose/Kubernetes upstream hostname and verify DNS/connectivity in the selected deployment.

This is a targeted static configuration correction. Phase 0 remains open.

### Phase 0 continuation — Kubernetes overlay renderability (2026-10-22)

- [x] Add a Kustomization entry point for the existing Kubernetes base resources.
- [x] Align backend Service selectors with the backend Deployment pod labels.
- [x] Expose the configured Kong upstream port `8080` while preserving the existing Ingress Service port `80`.
- [x] Add a static regression check that detects known missing overlay inputs and the missing frontend Deployment rather than silently claiming renderability.
- [ ] Decide the canonical frontend workload source or explicitly remove/retire the unsupported frontend Deployment patches, replicas, and dependent HPA/PDB.
- [ ] Supply reviewed `nginx-dev.conf`, `nginx-staging.conf`, and `nginx-prod.conf` inputs (or update references to approved existing files).
- [ ] Replace the missing staging `.env.staging` Secret generator input with a reviewed external-secret mechanism; do not materialize placeholder credentials as a Kubernetes Secret.
- [ ] Normalize namespace/namePrefix behavior and confirm HPA, PDB, Ingress, Service, and selector references in rendered output.
- [ ] Run `kustomize build` for dev, staging, and production, then validate rendered manifests and live Service endpoints in a cluster.

Static checks only; no Kustomize binary or Kubernetes cluster was available. Phase 0 remains open.

### Phase 0 continuation — Kubernetes namespace/name-prefix reconciliation (2026-10-22)

- [x] Align the dev, staging, and production namespace transformer values with the Namespace names produced by their `namePrefix` values (`dev-nidaw`, `staging-nidaw`, `prod-nidaw`).
- [x] Replace the base NetworkPolicy's hard-coded `nidaw` namespace selector with the stable `app.kubernetes.io/part-of: nidaw-platform` namespace label; preserve the explicit `kube-system` DNS egress selector.
- [x] Extend and pass the static Kubernetes overlay contract regression test for namespace/prefix alignment.
- [ ] Verify actual transformed Namespace names, workload namespaces, selectors, HPA targets, PDB selectors, and Ingress backend references using the repository's pinned Kustomize version.
- [ ] Resolve the absent frontend Deployment and missing environment-specific Nginx generator files; replace staging `.env.staging` Secret generation with the approved external-secret mechanism.

Static source validation only; no Kustomize binary or cluster validation was available. Phase 0 remains open.

### Phase 0 continuation — frontend workload source reconciliation (2026-10-23)

- [x] Trace the development Compose frontend build to `apps/consumer_app/Dockerfile.dev`; confirm consumer and driver Flutter web apps have separate Dockerfiles.
- [x] Confirm the admin console has a Vite/React build script but no Dockerfile in the inspected repository.
- [x] Confirm Kubernetes base has `nidaw-frontend` Service but no corresponding Deployment; all overlays still patch/scale that absent Deployment.
- [x] Add `scripts/audit/test-kubernetes-frontend-workload-evidence.py` and document findings in `phase-0-frontend-workload-source-reconciliation-2026-10-23.md`.
- [ ] Approve the canonical workload contract: consumer app vs separate consumer/driver/admin workloads, image build/publish process, and configuration injection strategy.
- [ ] Resolve missing overlay Nginx files and staging `.env.staging`; do not generate frontend Secrets from placeholder or public build-time configuration.
- [ ] Render all overlays with the pinned Kustomize version and validate transformed names, references, and Service endpoints in a cluster.

This pass is source-evidence reconciliation only. No frontend Deployment was invented, no secrets were fabricated, and Phase 0 remains open.

### Phase 0 continuation — deployment source-of-truth reconciliation (2026-10-23)

- [x] Trace the staging CI workflow: backend + consumer Flutter image builds, environment-specific compile-time API/WebSocket URLs, Helm deployment, and rollout checks.
- [x] Confirm Helm contains the frontend Deployment and Service missing from the separate Kustomize base.
- [x] Confirm the production workflow intentionally fails closed pending migration-ordering/backward-compatibility/rollback review; do not bypass the gate.
- [x] Add `scripts/audit/test-deployment-source-of-truth.py` and document evidence in `phase-0-deployment-source-of-truth-reconciliation-2026-10-23.md`.
- [ ] Decide whether Kustomize is a supported deployment path or legacy/unmaintained configuration; if supported, complete its missing workload and input files and render all overlays.
- [ ] Run Helm lint/template with the pinned Helm version and verify rendered names, probes, config, services, ingress, and secrets.
- [ ] Run CI-equivalent frontend/backend builds and runtime API/WebSocket smoke tests in the intended environment.
- [ ] Complete the production SQL migration review before removing or bypassing its fail-closed release guard.

Static source checks only; Docker, Helm, kubectl, and cluster validation are unavailable in this environment. Phase 0 remains open.

### Phase 0 continuation — Helm ingress and resource contract (2026-10-23)

- [x] Remove the global `rewrite-target: /` ingress annotation from dev, staging, and production values so root-path API/SPA requests are forwarded without being rewritten.
- [x] Correct production backend memory limit to 3Gi because its configured request is 2Gi and request > limit is invalid.
- [x] Add `scripts/audit/test-helm-deployment-contract.py` covering ingress rewrite, resource quantities, frontend port/probe contract, and the production fail-closed guard.
- [x] Parse 21 Helm, Kubernetes, and Compose YAML files and pass static contract regressions.
- [ ] Run `helm lint` and `helm template` for dev, staging, production using the repository-pinned Helm version/toolchain.
- [ ] Verify generated resource names, selectors, Secret references, TLS secret, and ingress routes against a staging cluster.
- [ ] Complete migration SQL ordering/backward-compatibility/rollback review before any production release; retain the existing fail-closed guard until approved.

Static checks do not replace chart rendering, image builds, or live cluster validation. Phase 0 remains open.


### Phase 0 continuation — external Kubernetes Secret preflight (2026-10-23)

- [x] Add `scripts/deploy/preflight-kubernetes-secrets.py` to verify target namespace, backend Secret type and required keys (`db-password`, `jwt-secret`, `kafka-brokers`, `redis-url`), and optional TLS Secret type/keys without printing Secret values.
- [x] Add a fake-kubectl regression test covering successful validation, missing backend keys, and invalid TLS Secret type; sentinel Secret values are asserted absent from output.
- [x] Add the preflight to staging deployment before Helm upgrade, and to both production deployment paths before Helm mutation if the existing production review gate is later approved.
- [ ] Run the preflight with a read-only identity against actual staging/production namespaces to confirm external Secrets exist and required keys are present.
- [ ] Verify the CI runner has the Python runtime and appropriate Kubernetes read permissions; no Secret values should be exposed in logs.
- [ ] Keep the production migration review gate fail-closed until SQL ordering, backward compatibility, and rollback behavior are approved.

Local mocked checks only; no cluster state was queried and no real Secret values were accessed. Phase 0 remains open.

### Phase 0 continuation — Secret preflight least-privilege review (2026-10-23)

- [x] Remove the preflight's cluster-scoped `get namespace` call; namespaced Secret reads now validate the actual dependency without requiring cluster-scoped namespace read permission.
- [x] Extend the fake-kubectl regression to fail if the preflight attempts a Namespace API read.
- [ ] Confirm the real CI identity has namespaced `get secrets` permission for only the required Secret resources, without granting unnecessary Secret list/watch or cluster-wide access.
- [ ] Validate against staging and production clusters without printing Secret values; retain the production migration-review gate.

Mocked tests only; live RBAC and Secret state remain unverified. Phase 0 remains open.

### Phase 0 continuation — Helm workload ServiceAccount RBAC review (2026-10-23)

- [x] Remove the Helm chart's unnecessary Secret-reader Role and RoleBinding from the application ServiceAccount template; the observed backend/migration configuration consumes Secrets through pod `secretKeyRef` references.
- [x] Add `scripts/audit/test-helm-serviceaccount-rbac.py` and document the difference between application ServiceAccount permissions and the CI deployment identity in `phase-0-helm-serviceaccount-rbac-review-2026-10-23.md`.
- [ ] Verify the CI/EKS deployment identity can `get` only the required Secret resources in the target namespace; do not grant Secret `list`, `watch`, or cluster-wide access for preflight.
- [ ] Render Helm templates and inspect the resulting ServiceAccount resources; run live `kubectl auth can-i` checks in staging.

Static validation only; no Helm rendering, cluster access, or live RBAC verification was available. Phase 0 remains open.

### Phase 0 continuation — Secret preflight identifier validation (2026-10-23)

- [x] Validate namespace names as RFC 1123 DNS labels and backend/TLS Secret names as DNS subdomains before invoking `kubectl`.
- [x] Extend fake-kubectl regression cases to prove malformed identifiers fail before any Kubernetes command is run.
- [x] Preserve redaction guarantees and existing successful/missing-key/TLS-type cases.
- [ ] Confirm effective CI identity permissions against staging and run the preflight against actual external Secret metadata without logging values.
- [ ] Run Helm rendering and cluster smoke tests; resolve Kustomize blockers if that path remains supported.
- [ ] Complete production migration review before altering the production fail-closed guard.

Static/mocked checks only. No live cluster or Secret state was accessed. Phase 0 remains open. See `phase-0-secret-preflight-identifier-validation-2026-10-23.md`.

### Phase 0 continuation — GitHub Actions step contract (2026-10-23)

- [x] Fix the staging API smoke-test step that incorrectly combined `uses` and `run` in a single GitHub Actions step.
- [x] Preserve the harden-runner audit step and run health/readiness checks in a separate shell step.
- [x] Add `scripts/audit/test-github-workflow-step-contract.py`; verify all workflow steps define exactly one of `uses` or `run`.
- [ ] Run GitHub Actions workflow validation and an actual staging workflow in the repository environment.
- [ ] Validate effective CI permissions against the target EKS namespaces and required external Secrets.

Static workflow correction only; no staging or production workflow was executed. Phase 0 remains open.

### Phase 0 continuation — deployment workflow security contract (2026-10-23)

- [x] Set least-privilege default `contents: read` permissions for staging and production deployment workflows.
- [x] Scope GHCR `packages: write` to image-build jobs and `contents: write` to production release creation.
- [x] Remove GITHUB_TOKEN permissions from notification-only jobs.
- [x] Pass manually supplied production version through an environment variable rather than interpolating it into shell source in validation/output steps.
- [x] Add `scripts/audit/test-deployment-workflow-security-contract.py` and preserve the production migration-review guard.
- [ ] Validate effective GitHub token permissions, AWS IAM/EKS permissions, GHCR access, and staging workflow behavior in the repository environment.

Static workflow security correction only. No live deployment or cluster permission check was performed. Phase 0 remains open.

### Phase 0 continuation — production validation and migration gate separation (2026-10-23)

- [x] Move the production migration fail-closed step out of `validate` so tests and security checks can execute.
- [x] Require the image build job to depend on both successful validation and the still-failing migration review gate.
- [x] Extend deployment workflow security regression to check the gate dependencies and retained fail-closed behavior.
- [ ] Verify scanner CLI installation (`trivy`, `gitleaks`) in the actual GitHub-hosted runner or provision pinned actions/tools.
- [ ] Run workflow validation and confirm test/scan jobs execute while production build remains blocked.

No production release was enabled. Phase 0 remains open.


### Phase 0 continuation — production security scanner provisioning (2026-10-23)

- [x] Replace unprovisioned `trivy`/`gitleaks` shell invocations with the Trivy GitHub Action, which provisions its scanner.
- [x] Configure explicit filesystem vulnerability, misconfiguration, and secret scanning for CRITICAL/HIGH findings and fail on findings.
- [x] Extend the workflow security contract test to enforce scanner configuration and retain the production migration fail-closed gate.
- [ ] Run the action in GitHub Actions to verify scanner provisioning, database download, and real scan execution.
- [ ] Run `actionlint` and confirm the repository's actual workflow behavior.

Static/local checks only; no GitHub-hosted scan was executed. Production remains blocked by the migration-review gate. See `phase-0-production-security-scanner-provisioning-2026-10-23.md`.


### Phase 0 continuation — staging smoke-test runner visibility ordering (2026-10-23)

- [x] Move `step-security/harden-runner` to the first step of the staging smoke-test job so runner egress visibility begins before checkout and smoke-test commands.
- [x] Extend the workflow step-contract regression to enforce the hardening step's position and audit policy.
- [ ] Run the staging workflow and inspect network visibility output in GitHub Actions; this local check cannot establish runtime telemetry or egress behavior.

Static workflow validation only. Phase 0 remains open.


## Phase 0 update — explicit Helm runner toolchain (2026-10-23)

- [x] Install a pinned Helm 3 CLI in the staging deployment job and production canary/full-deployment jobs.
- [x] Verify the installed Helm version before the first Helm command.
- [x] Add static regression coverage for action presence, pinned version, and step order.
- [ ] Run the workflow with GitHub-hosted runners and render the chart with the pinned CLI.
- [ ] Validate staging deployment behavior against the real cluster and external Secret metadata.
- [ ] Keep production migration execution blocked until ordering, compatibility, and rollback review is complete.

### Phase 0 continuation — explicit kubectl runner provisioning (2026-10-23)

- [x] Add explicit kubectl setup to staging, production canary, and full production deployment jobs.
- [x] Resolve the target EKS cluster's Kubernetes minor version and select the latest published kubectl patch in that minor; fail closed on malformed or unavailable version data.
- [x] Verify the installed kubectl client before kubeconfig-dependent preflight and deployment commands.
- [x] Extend the static workflow contract test to enforce setup and ordering; all five workflow YAML files parse and targeted workflow/security/source-of-truth checks pass.
- [ ] Execute workflows on GitHub-hosted runners, confirm actual EKS versions/permissions, render the Helm chart, and validate rollout behavior against staging.

This is a runner-tooling reproducibility improvement only. Phase 0 remains open; production migration review remains fail-closed.

### Phase 0 continuation — Kubernetes CLI credential and preflight ordering (2026-10-23)

- [x] Strengthen the GitHub Actions workflow contract test to require AWS credential configuration before EKS cluster-version lookup in staging, production canary, and full production deploy jobs.
- [x] Enforce that the resolved `kubectl` client is installed and verified before kubeconfig setup, and that the external Kubernetes Secret preflight runs only after kubeconfig is configured.
- [x] Enforce that cluster-dependent `kubectl` commands do not run before kubeconfig setup; the local client-version check is explicitly exempt.
- [x] Re-run deployment workflow, security, Helm, Kubernetes overlay, Secret preflight, RBAC, Kong path, and product-import static checks.
- [ ] Run the workflows against GitHub-hosted runners and the actual EKS environments; static YAML and ordering checks do not validate cloud permissions, action downloads, cluster access, or rollout behavior.

This adds regression protection for deployment step ordering only. Phase 0 remains open; the missing `haven` and `vorax` Go module directories and the incomplete Kustomize overlays remain explicit findings, not reasons to create placeholder modules or invented workloads.

## 2026-10-23 — Haven/Vorax application implementation checkpoint

- [x] Added in-process Haven and Vorax HTTP module route registration to the Go composition root.
- [x] Added hotel/restaurant discovery and detail endpoints against the existing schema.
- [x] Added authenticated booking/order listing and caller-ownership checks.
- [x] Added transactional Vorax order creation with server-authoritative prices and order-item snapshots.
- [x] Added Haven date-scoped inventory migration and transactional capacity reservation/release; existing inventory is not guessed.
- [x] Added Kong route for administrator inventory provisioning.
- [ ] Apply migration 019 and verify behavior against PostgreSQL.
- [ ] Refactor SQL out of HTTP handlers into dedicated application and infrastructure packages.
- [x] Replace Haven/Vorax consumer-app mock data and implement API-backed data repositories/BLoCs for discovery, booking, menus, orders and tracking.
- [ ] Add end-to-end booking/payment and food-order/payment/fulfillment orchestration.
- [ ] Complete product-wide modular-monolith boundary review; Phase 0 is still open.
- [x] Aligned Haven/Vorax Kong route coverage and route-scoped JWT enforcement with the new module endpoints.
- [x] Added the Haven inventory rollback SQL and made the migration-up runner skip down-migration files.


### Application restructuring — Haven/Vorax domain policy extraction (2026-10-23)

- [x] Added Haven domain policy functions for stay-date/occupancy validation, calendar-night calculation, and reservation total calculation.
- [x] Updated Haven HTTP handlers to delegate these rules to the domain package rather than own the business policy.
- [x] Added Vorax domain order-total calculation that validates non-negative finite prices/fees, quantities, minimum subtotal, and single-currency orders.
- [x] Updated Vorax order creation to use the domain calculator with prices read and locked from the database; client-supplied totals remain ignored.
- [x] Added deterministic unit tests for valid/invalid booking rules and Vorax total, currency, and invalid-value cases.
- [ ] Continue moving persistence transactions out of HTTP handlers into application/infrastructure packages.
- [ ] Run Haven/Vorax HTTP package tests and integration tests when Go dependencies are available; current environment timed out while downloading dependencies.

This is an application-layer/domain-boundary step, not completion of the overall modular-monolith restructuring.

### Application restructuring — Haven booking use-case/persistence separation (2026-10-24)

- [x] Introduce a Haven application service with an explicit booking command, result, and persistence interface.
- [x] Move booking creation's transactional PostgreSQL operations into the Haven infrastructure adapter.
- [x] Keep HTTP handling responsible for request parsing, error mapping, and response serialization.
- [x] Add application-service tests for validation-before-persistence and valid delegation.
- [x] Extract Haven cancellation and inventory-administration SQL from HTTP handlers; catalog and booking read SQL remain pending.
- [ ] Apply the same application/repository split to Vorax order creation and read paths.
- [ ] Run application/HTTP tests and PostgreSQL concurrency integration tests when dependency and database access are available.

This is a partial boundary improvement. It does not complete Phase 0 or the overall modular-monolith restructuring.

### Application restructuring — Haven lifecycle persistence separation (2026-10-24)

- [x] Move booking cancellation transaction from HTTP handler into Haven PostgreSQL adapter behind application service.
- [x] Move room-inventory provisioning upsert from HTTP handler into Haven PostgreSQL adapter behind application service.
- [x] Add application tests for cancellation delegation and invalid inventory capacity rejection.
- [x] Confirm Haven HTTP mutation handlers no longer contain cancellation/inventory SQL.
- [ ] Extract Haven hotel discovery/detail and booking list/detail reads into application/repository boundaries.
- [ ] Extract Vorax order creation and read paths into application/repository boundaries.
- [ ] Run Haven application/adapter/HTTP tests when Go dependencies are available.

### Application restructuring — Haven booking read-path separation (2026-10-24)
- [x] Added application-level booking list/get use cases with bounded pagination and user-scoped access.
- [x] Moved booking list/get SQL into the Haven PostgreSQL adapter.
- [x] Updated HTTP handlers to delegate booking reads through the application service.
- [x] Added application tests for reader delegation and pagination bounds.
- [x] Extract hotel catalog list/detail reads from the Haven HTTP adapter.
- [ ] Run Haven application, PostgreSQL adapter, and HTTP package tests when Go dependencies are available.

### Application restructuring — Haven hotel catalog separation (2026-10-24)

- [x] Introduce a catalog application service and hotel reader contract for discovery/detail use cases.
- [x] Move active-hotel list/detail SQL and row scanning into the Haven PostgreSQL catalog adapter.
- [x] Keep HTTP handlers responsible for parsing filters/IDs, error mapping, and response serialization.
- [x] Add catalog application tests for delegation and pagination defaults/bounds.
- [ ] Apply the same application/repository split to Vorax order creation and read paths.
- [ ] Run Haven application, PostgreSQL adapter, and HTTP package tests when dependencies are available.

This closes the known direct-SQL catalog/read paths in Haven HTTP handlers, but Haven still shares the booking adapter as the lifecycle writer and the overall product restructuring remains in progress.

### Application restructuring — Vorax order creation separation (2026-10-24)

- [x] Introduce a Vorax order application service and explicit create-order command/result contracts.
- [x] Move restaurant locking, server-side menu price reads, total calculation, order/order-item inserts, and commit into the PostgreSQL adapter.
- [x] Keep request parsing and basic input validation in HTTP; HTTP no longer owns the order transaction.
- [x] Preserve user identity, restaurant ownership checks for menu items, item availability checks, currency/minimum-order validation, and price snapshots.
- [x] Add application tests for valid delegation and invalid item rejection before persistence.
- [ ] Extract Vorax restaurant/menu discovery and order list/tracking reads from HTTP.
- [ ] Run Vorax application/adapter/HTTP and PostgreSQL transaction/concurrency tests when dependencies and database access are available.

This is a partial Vorax boundary improvement. Restaurant/menu queries and order list/tracking SQL remain in the HTTP adapter; cross-product order/payment/fulfilment orchestration remains unverified.

### Application restructuring — Vorax read-path separation (2026-10-24)

- [x] Add a Vorax application read service and explicit restaurant/order reader contracts.
- [x] Move restaurant discovery/detail, menu listing, order listing, and order tracking SQL into a PostgreSQL adapter.
- [x] Keep user-scoped order listing/tracking queries scoped by authenticated user ID.
- [x] Bound read pagination in the application service (default 20, maximum 100).
- [x] Remove direct SQL/database access from the Vorax HTTP router for discovery, menu, and order read paths.
- [x] Add application tests for read pagination behavior.
- [ ] Run Vorax application, PostgreSQL adapter, and HTTP package tests when dependencies are available.
- [ ] Add PostgreSQL integration tests for read ownership, not-found mapping, and result compatibility.

Vorax's principal HTTP routes now delegate persistence to application/infrastructure packages for both order creation and reads. Product-wide modular-monolith acceptance and cross-product payment/fulfilment orchestration remain open.

### Application restructuring — Vorax read-path separation and Corpus orchestration review (2026-10-24)

- [x] Add a Vorax application read service and explicit restaurant/order reader contracts.
- [x] Move restaurant discovery/detail, menu listing, order listing, and order tracking SQL into a PostgreSQL adapter.
- [x] Keep order reads scoped to the authenticated user and bound pagination in the application service.
- [x] Remove direct SQL/database access from the Vorax HTTP router for discovery, menu, order list, and tracking routes.
- [x] Fix the missing shared database import in Haven's HTTP composition adapter, found while reviewing the latest package boundaries.
- [x] Document concrete Corpus orchestration risks found in the current implementation.
- [ ] Refactor Corpus policy evaluation, persistence, and orchestration behind explicit application ports.
- [ ] Define and implement transactional Corpus outbox ownership/retry semantics before relying on event publication.
- [ ] Replace untyped service-specific booking data with validated typed contracts and add failure-path tests.
- [ ] Run Haven/Vorax application, adapter, and HTTP tests when Go dependencies are available; add PostgreSQL integration coverage.

The latest code audit uncovered a missing import in Haven that would prevent the HTTP package from compiling; the import is now restored. Dependency availability still prevents compiler/test confirmation. Corpus remains a material cross-product orchestration blocker; this review records the evidence and required follow-up without claiming it is fixed.

### Application restructuring — Corpus policy validation hardening (2026-10-24)

- [x] Extract deterministic ride/hotel/food/freight policy evaluation into a database-independent domain package.
- [x] Reject missing or wrongly typed service-specific policy fields instead of interpreting them as zero values.
- [x] Require a finite, non-negative booking amount for approval and spending-limit decisions.
- [x] Reject unsupported service types and add focused policy evaluator unit tests.
- [x] Fail closed when approval is required but no eligible approver can be resolved.
- [ ] Replace generic booking maps with explicit versioned product-specific contracts.
- [ ] Extract employee/policy/approver reads and booking writes behind application repository ports.
- [ ] Implement Corpus-owned transactional outbox and retry/idempotency handling for created and downstream handoff events.
- [ ] Add approval escalation/state-transition tests and PostgreSQL transaction/outbox integration tests.
- [ ] Execute Corpus tests after dependencies become available; current environment prevented dependency resolution, so tests remain unverified.

This checkpoint hardens policy input handling and prevents orphaned pending-approval bookings, but it does not close the larger Corpus orchestration or event-delivery reliability gap.

### Corpus application boundary and outbox (2026-10-24)

- [x] Define Corpus application repository and booking-event ports.
- [x] Move employee, active-policy, approver, and booking SQL out of the command handler into a PostgreSQL adapter.
- [x] Persist booking and outbound event records in one database transaction.
- [x] Add Corpus outbox migration and retrying at-least-once dispatcher implementation.
- [x] Add fake-repository command tests for success, missing approver, and persistence failure.
- [x] Wire Corpus handler into authenticated `POST /api/v1/corpus/bookings` and the server composition root.
- [x] Start the Corpus outbox dispatcher only after checking the outbox table exists.
- [x] Add a proposed Corpus schema migration for `corporate_bookings`, `corporate_employees`, and `travel_policies`; production-schema reconciliation remains pending.
- [ ] Run Corpus Go package tests and PostgreSQL outbox integration tests in an environment with dependencies and PostgreSQL available.
- [ ] Establish downstream idempotency contracts and approval/escalation workflow semantics.
- [x] Correct shared Kafka publisher topic selection so `EventBus.Publish(ctx, topic, event)` routes to the requested topic.

### Application restructuring — Corpus schema ownership and outbox startup wiring (2026-10-24)

- [x] Add forward migration for Corpus corporate account, employee, travel-policy, and corporate-booking tables referenced by the repository adapter.
- [x] Add an explicitly destructive rollback migration for the new Corpus schema.
- [x] Wire the outbox dispatcher into the server composition root only when the outbox table is detected.
- [x] Add static regression assertions for schema columns, atomic repository transaction, dispatcher retry/claim logic, and guarded startup.
- [ ] Review migration against deployed corporate data and apply only through the reviewed migration process.
- [ ] Add a PostgreSQL migration test and integration tests for booking/outbox atomicity, concurrent dispatch, retries, and crash recovery.
- [x] Define the initial authenticated Corpus HTTP contract and resolve the authenticated user to an active corporate employee rather than trusting a client-supplied employee ID.
- [x] Wire the create-booking handler after establishing the initial identity/authorization boundary.
- [ ] Define downstream event idempotency contracts and approval lifecycle transitions.
- [ ] Run Corpus application/infrastructure/server package tests when Go dependencies are available.

Static checks passed for this checkpoint. The schema has not been applied to a live database, and Go compilation/runtime behavior remains unverified in the current dependency-restricted environment.

### Application restructuring — Corpus authenticated booking API boundary (2026-10-24)

- [x] Add authenticated `POST /api/v1/corpus/bookings` and register it in server composition.
- [x] Derive user identity from the validated auth context; do not accept a client-supplied employee identifier.
- [x] Resolve active employee membership using authenticated user ID and selected corporate account ID; require active corporate account.
- [x] Persist the resolved employee membership ID rather than conflating it with the authenticated user ID.
- [x] Add static regression assertions for route protection, identity mapping, and composition wiring.
- [x] Add transport tests for absent authentication context, client-supplied employee ID rejection, authenticated-user propagation, and safe error responses.
- [ ] Run HTTP/application/infrastructure/server package compilation and tests when dependencies are available.
- [ ] Add HTTP tests for unauthorized requests, malformed/oversized bodies, membership denial, and successful creation.
- [ ] Add PostgreSQL integration tests and review migration compatibility against deployed data.
- [ ] Replace generic `booking_data` maps with distinct compile-time typed product payload schemas.
- [x] Add explicit schema version 1 and stable outbox event ID to the event envelope; consumer-side version handling and idempotency remain pending.

The route is now wired, but this is not a claim of production readiness: Go tests could not run because dependencies were unavailable offline, and no live PostgreSQL integration has been performed.

### Application restructuring — Corpus event contract versioning (2026-10-24)

- [x] Add a backward-compatible migration assigning schema version 1 to existing outbox records.
- [x] Persist an explicit positive schema version for newly created Corpus outbox records.
- [x] Publish the stable outbox event ID and schema version in the shared event envelope.
- [x] Add static regression assertions for migration, repository persistence, dispatcher propagation, and application event declarations.
- [ ] Replace generic service-specific booking data with product-owned typed payload schemas and compatibility tests.
- [ ] Confirm all consumers preserve/deduplicate event IDs and deliberately handle schema versions.
- [ ] Execute Go tests and PostgreSQL integration tests when dependencies and a test database are available.

The version field is an initial compatibility contract, not proof that downstream consumers already enforce version handling or idempotency.


### Application restructuring — Corpus typed booking contracts (2026-10-24)

- [x] Define version-1 typed payload contracts for rides, hotels, food, and freight policy inputs.
- [x] Validate service-specific required fields before Corpus policy evaluation and persistence.
- [x] Preserve extra product-specific payload fields for downstream compatibility while typing policy-critical fields.
- [x] Add contract tests and static architecture regression assertions.
- [ ] Migrate persistence and downstream event payloads to product-owned typed schemas after confirming each product's authoritative contract.
- [ ] Execute Corpus Go tests and full package compilation when dependencies are available.
- [ ] Add consumer contract compatibility and idempotency tests for all downstream products.

The typed contracts validate the current policy-critical version-1 fields; they do not yet replace the generic JSON payload stored and forwarded by Corpus.


### Application restructuring — Corpus approval lifecycle (2026-10-24)

- [x] Add explicit approve/reject application command behind the Corpus booking repository port.
- [x] Register authenticated approve/reject routes for corporate booking decisions.
- [x] Resolve approval authority from the authenticated user and the booking's assigned active approver membership; do not accept an approver employee ID from the client.
- [x] Lock the pending booking and atomically update its decision state with an outbox event.
- [x] Add approval decision timestamp/notes migration and an explicit destructive rollback.
- [x] Add application tests and static approval lifecycle boundary assertions.
- [ ] Run Corpus Go package tests and compilation when dependencies are available.
- [ ] Run PostgreSQL integration tests for concurrent decisions, transaction rollback, and event atomicity.
- [ ] Verify downstream consumers handle approved/rejected events idempotently and enforce product-specific contract compatibility.

The current approval decision endpoint transitions an assigned pending booking to `confirmed` or `rejected`. The database transaction and outbox insertion are implemented in the adapter, but runtime behavior has not been verified against PostgreSQL because the required Go modules are unavailable in the current offline environment.

## Logix customs boundary checkpoint (2026-10-24)

- [x] Extract customs persistence behind an application-owned repository port; see `logix-customs-persistence-boundary-2026-10-24.md`.
- [x] Move multi-row customs submission/status writes into PostgreSQL adapter transactions and verify affected-row counts.
- [x] Add fail-closed validation for invalid package counts, non-finite declared values, tariff exemption lookup failures, and unsupported customs statuses.
- [x] Add static architecture assertions and application unit tests for the new boundary and validation.
- [ ] Run Logix Go unit/package tests in a dependency-enabled environment; current attempt is blocked before compilation because modules are unavailable offline.
- [ ] Add/verify the authoritative customs schema migration and run PostgreSQL integration tests.
- [ ] Mount Logix in the composition root and prove route/worker reachability before treating this as a runtime capability.
- [ ] Replace direct post-commit customs event publishing with transactional outbox delivery and define idempotent external customs submission/reconciliation.


### Logix customs follow-up — terminal state protection (2026-10-24)

- [x] Prevent status polling from overwriting terminal `cleared` and `rejected` declarations by narrowing the SQL transition predicate.
- [x] Reject unsupported repository target statuses and negative duties/taxes.
- [x] Add static regression assertions for terminal-state protection.
- [ ] Compile and run Logix package tests when Go dependencies are available.
- [ ] Verify transition behavior against the deployed customs schema with PostgreSQL integration tests.

This is a targeted persistence guard, not proof of end-to-end customs workflow readiness. The customs schema, runtime composition, and transactional event outbox remain open.


### Logix follow-up — transactional customs event outbox (2026-10-24)

- [x] Persist `logix.customs.submitted` and `logix.customs.cleared` events in the same PostgreSQL transaction as the declaration/shipment transition.
- [x] Add migration 024 for a versioned Logix event outbox with lease recovery, retry scheduling, and publication metadata.
- [x] Add a process-owned dispatcher that starts only when the outbox schema is present.
- [x] Remove direct post-commit publication from the customs application service to avoid the state-committed/event-lost failure window.
- [x] Add static assertions for transaction coupling, retry behavior, and runtime worker wiring.
- [ ] Run Logix package tests and PostgreSQL integration tests in an environment with Go dependencies and the authoritative schema.
- [ ] Verify downstream consumers deduplicate by event ID and validate schema version 1.
- [ ] Make external customs submission idempotent or add reconciliation for the case where the authority accepts a declaration but local persistence fails.

The outbox closes the local database-to-broker dual-write gap for submission and clearance events. It does not make the external customs authority call transactional, and delivery remains at-least-once.

### Shared event infrastructure — consumer offset commit safety (2026-10-24)

- [x] Replace auto-committing `ReadMessage` with `FetchMessage` and explicit offset commits after successful event processing.
- [x] Keep handler failures uncommitted after the configured retry budget so Kafka can redeliver them rather than silently dropping the event.
- [x] Make retry backoff cancellation-aware and validate consumer configuration before indexing topic configuration.
- [x] Define an explicit poison-message policy: malformed JSON and events without a type are logged and committed to avoid an infinite poison-pill loop.
- [x] Add unit tests for successful commit, failed handler, malformed message, commit failure, and missing topic configuration.
- [x] Add a static architecture regression script for the offset-commit contract.
- [ ] Run shared eventbus Go tests and package compilation in a dependency-enabled environment.
- [ ] Add broker-backed tests proving failed messages are redelivered after restart and successful messages are not redelivered after commit.
- [ ] Define a dead-letter or quarantine path for poison messages; current behavior intentionally logs and commits them, so investigation/replay must be handled operationally.

The change prevents the previous failure mode where `ReadMessage` committed the offset before handler execution and the consumer then logged exhausted retries but still advanced. Delivery is still at-least-once: handlers must be idempotent, and a crash after side effects but before commit can replay an event.


### Shared event infrastructure — independent reliable product subscriptions (2026-10-24)

- [x] Use configured Kafka brokers instead of hardcoded `localhost:9092` in shared subscriptions.
- [x] Give legacy best-effort subscriptions separate consumer groups so independent in-process subscribers do not compete for one copy of the event stream.
- [x] Add an error-aware reliable subscription API with explicit fetch/commit and cancellation-aware retry behavior.
- [x] Give notifications and telephony stable, product-specific consumer group IDs and route their handler errors into the reliable retry path.
- [x] Ensure a successful handler is not re-executed merely because the offset commit initially fails.
- [x] Add static regression assertions for configured brokers, independent groups, retry semantics, and product wiring.
- [ ] Run shared eventbus and consumer Go tests in a dependency-enabled environment.
- [ ] Add Kafka-broker integration tests for restart/redelivery, partition rebalancing, and commit failure.
- [ ] Add a durable dead-letter/quarantine workflow for malformed events; current poison-message policy logs and commits them.

The reliable path is at-least-once and can block a consumer partition while a handler keeps failing. Handlers must be idempotent. Test-only buses that implement only the legacy `EventBus` contract use a compatibility fallback that cannot provide broker-backed retries.

### Notifications consumer idempotency correction (2026-10-24)

- [x] Prefer the stable outbox `event_id` for notification deduplication instead of assuming the event ID equals a ride ID.
- [x] Prevent legitimate repeated `driver.arriving` tiers from collapsing into one `(type, ride_id)` key when legacy producers omit event IDs.
- [x] Distinguish legacy `ride.destination_changed` events by destination identity; leave events unkeyed when no safe identity is available rather than suppressing later changes.
- [x] Add static regression assertions for stable event identity and repeatable-event fallback behavior.
- [ ] Run notification Go package tests when required modules are available; validate durable duplicate suppression against PostgreSQL in an integration environment.

The outbox dispatchers generate a stable random UUID per outbox record; they do not set `event_id = ride_id`. Using the outbox ID correctly deduplicates re-delivery of one record while allowing multiple legitimate transitions for the same ride.

### Cross-product event topic routing correction (2026-10-24)

- [x] Correct the mistaken assumption that KafkaBus rewrites every topic to `nidaw.events`; it publishes to the explicit topic argument.
- [x] Add reliable multi-topic subscriptions with stable topic-qualified group IDs.
- [x] Subscribe Notifications to the currently observed ride, location, and payment producer topics.
- [x] Subscribe Telephony to both the legacy shared topic and actual ride lifecycle topic.
- [x] Subscribe WebSocket fan-out to the observed ride, location, and payment topics.
- [x] Subscribe the driver-arriving watcher to the location topic as well as the legacy shared topic.
- [x] Make MemoryBus topic-aware so tests cannot hide production topic mismatches.
- [x] Add topic-routing regression tests and static architecture assertions.
- [ ] Run Go package tests in a dependency-enabled environment and verify broker topic/ACL configuration in integration tests.
- [ ] Complete the event schema registry/matrix for all Corpus, Haven, Vorax, and Logix producers and consumers.

This correction fixes source-level subscription mismatches. It does not establish that all topics exist in deployed Kafka, that ACLs allow these consumers, or that all cross-product payloads are schema-compatible.

### Phase 6 continuation — cross-product event contract catalogue (2026-10-24)

- [x] Add an initial machine-readable event catalogue for observed Corpus booking, Logix customs/load, and Nidus ride events with schema versions, source paths, topics, fields, and consumer status.
- [x] Add structural regression checks for catalogue completeness, source-file existence, and required Corpus/Logix handoff entries.
- [ ] Expand the catalogue to every producer/consumer path and all five products; current entries are explicitly partial.
- [ ] Add runtime provider/consumer payload validation and contract compatibility tests.
- [ ] Mount and integration-test Corpus downstream consumers and Logix freight handoffs; runtime composition remains incomplete.
- [ ] Migrate Logix `logix.load.matched` from direct legacy publication to a versioned durable contract after transaction ownership is traced.

### Phase 6 follow-up — versioned Logix load-match publication intent (2026-10-25)

- [x] Replace the legacy direct `logix.load.matched` publish with an application port and durable Logix outbox insertion.
- [x] Set the event contract to schema version 1 and document required fields and source paths in the event catalogue.
- [x] Add static regression checks for validation, transactional insertion, versioning, and explicit consumer/runtime gaps.
- [ ] Mount the load-matcher workflow through the canonical Logix runtime composition; no active call site was found during this checkpoint.
- [ ] Verify `loads` and `carriers` schema/query compatibility against the authoritative migration chain and test with PostgreSQL.
- [ ] Add consumer contract tests and Kafka-backed delivery/replay tests.

This advances one event path but does not accept Phase 6, Phase 7, or Phase 8.


### Logix outbox schema startup preflight (2026-10-25)

- [x] Replace the outbox table-exists-only startup check with a schema contract preflight.
- [x] Require every column consumed or updated by the Logix dispatcher before starting it.
- [x] Fail closed with a diagnostic warning when the table is absent or partially migrated.
- [x] Add static regression assertions for schema preflight and runtime composition.
- [ ] Run Logix Go package tests and validate the preflight against PostgreSQL instances at supported migration levels.
- [ ] Add a versioned migration compatibility test that exercises the dispatcher query against the authoritative schema.

This prevents a partially applied migration from being treated as ready merely because `logix_event_outbox` exists. It does not verify the separate `loads` and `carriers` schema used by load matching, which remains unresolved and is not silently inferred here.


### Logix schema evidence gate (2026-10-25)

- [x] Extend the schema-ownership inventory with a targeted scan for Logix SQL references lacking checked-in PostgreSQL migration evidence.
- [x] Document the load-matcher query assumptions and missing authoritative schema evidence without inventing tables or columns.
- [ ] Establish the authoritative owner/schema source for `carriers`, `customs_declarations`, and `shipments`; determine whether `loads` is externally persisted or only represented as a domain entity.
- [ ] Add clean-database PostgreSQL migration/query contract tests before enabling Logix load matching or accepting the customs persistence path.
- [ ] Confirm the runtime composition call site and exercise successful and failed load-match publication end-to-end.

The inventory is a static audit, not proof of absence from deployed databases. No schema has been fabricated as part of this checkpoint.


### Logix load-matcher persistence boundary (2026-10-25)

- [x] Introduce an application-level `CarrierRepository` port so matching/scoring no longer depends directly on the shared PostgreSQL client.
- [x] Move carrier SQL and row scanning into the Logix PostgreSQL adapter; propagate query, scan, and row-iteration errors.
- [x] Add application unit tests for missing repository, no candidates, best-candidate selection, deterministic score ties, and outbox-write failure.
- [x] Add static architecture checks that the application service contains no carrier SQL and the adapter implements the port.
- [ ] Validate the adapter against the authoritative carrier schema and clean PostgreSQL database before runtime wiring.
- [ ] Add deterministic tie-breaking and database-backed query/scan contract tests after schema ownership is established.

This is a boundary refactor only. It does not resolve the missing schema evidence or activate `LoadMatcher` in runtime composition.

### Logix customs tariff calculation guard (2026-10-25)

- [x] Reject non-finite or negative tariff rates before computing duties.
- [x] Reject non-finite or negative calculated duties before persistence.
- [x] Remove the unsupported blanket 50% duty reduction for any returned exemption identifier.
- [x] Fail closed when exemptions are present but no explicit calculation policy is available.
- [x] Add regression tests and static architecture guards for the above cases.
- [ ] Integrate an authoritative exemption policy and verify it with domain/legal owners before allowing exempt declarations through this path.


### Logix customs authority submission contract (2026-10-25)

- [x] Reject missing declaration/shipment identifiers before external submission.
- [x] Reject blank external declaration references before local persistence.
- [x] Reject zero declaration IDs before polling the authority.
- [x] Add regression coverage and static checks for invalid input and persistence-failure reporting.
- [ ] Establish authority-side idempotency or reconciliation semantics for remote acceptance followed by local persistence failure.
- [ ] Validate the customs tables against an authoritative schema and run PostgreSQL contract tests.

The service still cannot promise safe retries across the external authority and local database boundary.

### Logix customs authority polling validation (2026-10-28)

- [x] Reject negative and non-finite duties/taxes from the authority before repository mutation.
- [x] Preserve authority polling error context for diagnosis.
- [x] Add unit regression cases for invalid authority amounts and valid status persistence.
- [x] Add static architecture assertions for the validation boundary.
- [ ] Run Go unit tests in an environment with the declared modules available.
- [ ] Verify authority amount/currency semantics and PostgreSQL behavior against authoritative contracts.

### Final restructuring acceptance review (2026-10-28)

- [x] Re-run all 16 static architecture checks.
- [x] Format Go sources with `gofmt` and verify no unformatted files remain.
- [x] Parse all Python scripts and validate shell-script syntax.
- [x] Run migration-runner mock regression tests and check contiguous up-migration numbering.
- [x] Repair malformed Grafana dashboard JSON and add a strict JSON/panel-ID regression check.
- [ ] Compile and run Go tests in an environment with declared dependencies available; current offline attempt is blocked before compilation.
- [ ] Run Nidus regression tests; no runtime pass is claimed in this environment.
- [ ] Execute migrations and API flows against disposable PostgreSQL and Kafka; tools/services are unavailable here.
- [ ] Render/deploy the active Helm path and validate runtime routing/authorization in an environment-backed test.
- [ ] Resolve authoritative Logix schema ownership and complete event-consumer contract evidence before enabling the affected workflows.

See `docs/architecture/restructuring-acceptance-review-2026-10-28.md` for the full evidence-based handoff decision and known blockers. Static validation is improved, but full runtime acceptance remains open.
