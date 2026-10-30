# Phase 1 Migration Log

## Scope completed in this change

Moved the three existing applications and the Go modular monolith to their canonical primary destinations:

- `backend/` → `services/api/`
- `frontend/` → `apps/consumer_app/`
- `driver_app/` → `apps/driver_app/`
- `admin_console/` → `apps/admin_console/`

Updated path references across 178 text files, including GitHub Actions workflows, Compose build contexts and bind mounts, scripts, Makefile targets, VS Code launch configurations, and documentation. Corrected the root `make dev` target to use the actual Compose base + development overlay. Routine `make clean` now stops the local Compose stack without deleting volumes or destroying infrastructure; destructive Terraform teardown is a separate `destroy-infra` target.

Generated `node_modules`, `dist`, and TypeScript build-info output were removed from the migrated admin application directory. Lockfiles were retained. `.gitignore` now excludes common generated artifacts and local environment secrets while permitting `.env.example` files.

## Explicitly not moved yet

- `platform/gateway/` remains at repository root; planned destination is `platform/gateway/`.
- `docker/` remains at repository root; planned destination is `platform/docker/`.
- Platform assets and SQL assets have since been moved; see the Phase 1 migration sections below.
- `infrastructure/`, `config/`, analytics, ML, legal, security, and existing docs remain in place pending their own reference and deployment review.

These remaining moves are intentionally separate because deployment definitions contain multiple competing path assumptions. No new empty service directories were created.

## Verification

- Static stale-path scan for old primary application directories: passed for the patterns checked.
- `go test ./...`: blocked because required Go modules are not cached and network retrieval is unavailable.
- Admin `npm ci --offline`: blocked because required package tarballs are not present in the npm cache. The admin build passed before the directory move; a post-move build must be rerun with dependencies available.
- Flutter SDK unavailable; mobile builds/tests not run.
- Docker, Helm, Terraform, and PostgreSQL CLI tools unavailable; Compose/deployment/migration runtime validation not run.
- No Git metadata was included in the uploaded archive, so Git history preservation and `git diff` verification cannot be performed in this environment.

## Known migration follow-ups

1. Review the entire changed path surface in a Git checkout and inspect unintended text replacements.
2. Validate all workflow action artifact paths, especially those relative to workspace root versus configured `working-directory`.
3. Finish the platform/data directory moves only after all relative Compose, Dockerfile, Helm, Kustomize, script, and CI paths are updated as one change.
4. Run Go, Flutter, admin, Compose, and migration checks in a dependency-enabled environment.

## Additional verification details

- `bash -n scripts/*.sh`: passed shell syntax parsing.
- PyYAML parsing passed for the core GitHub Actions workflows and Compose base/dev/prod files; YAML parsing does not validate Docker Compose semantics.
- Static stale-path scan for old primary app directory references passed.
- `make -n dev test clean destroy-infra` prints the intended new commands and path locations.
- Initial static Compose scan found missing PostgreSQL and monitoring config paths. These were corrected by removing the absent custom PostgreSQL config and pointing monitoring mounts at the checked-in config files; Grafana provisioning and Promtail config were added. The Feast Dockerfile was missing at this checkpoint and has since been added. Runtime Compose validation remains blocked because Docker is unavailable.
- `gofmt -l` reports multiple existing Go files with formatting differences. They were not mass-formatted as part of a path-only migration to avoid unrelated source churn; handle in the build/quality phase with review.

## Follow-up hardening: monitoring mounts and deployment safety

- Corrected Compose monitoring bind mounts to the actual checked-in Prometheus, Loki, Alertmanager, and Grafana directories/files. Prometheus alert rules now mount at the path configured by `prometheus.yml`.
- Added minimal Grafana datasource/dashboard provisioning and a Promtail configuration so the referenced bind-mount paths exist. These files still require runtime validation against the pinned container images.
- Removed the nonexistent custom PostgreSQL config mount and custom config-file command from the base Compose service; PostgreSQL now uses the image's default configuration rather than failing on a missing bind mount.
- Replaced the misleading one-click production deploy script with a fail-closed preflight. It uses the actual `infrastructure/environments/<environment>` and `platform/helm/nidaw` paths, makes no production mutations, and explicitly reports the missing driver workload and unapproved production migration-safety contract. It refuses an infrastructure plan while the deployment contract remains incomplete.
- Docker Compose runtime validation remains blocked because Docker is not installed in this environment. The analytics Feast Dockerfile has since been added; its dependency installation and runtime remain unverified.
- Moved SQL migrations and seed assets from `database/` to `data/{migrations,seeds}/` and updated script defaults, devcontainer mounts, application comments, and architecture docs. Production safety still requires separating sample/test seed data from ordered migrations before automated production migration execution is enabled.

## Platform directory migration

- Moved `api_gateway/` to `platform/gateway/`, `docker/` to `platform/docker/`, `k8s/` to `platform/kubernetes/`, `helm/` to `platform/helm/`, and `monitoring/` to `platform/monitoring/`.
- Updated root-relative paths in scripts, CI, docs, VS Code tasks, and configuration. Adjusted Compose build contexts to account for the additional directory depth. Relative path checks and Compose runtime validation are still required; Docker/Kubernetes/Helm CLIs are unavailable in this environment.
- Legacy deployment workflows and operations guides still need a dedicated review before being treated as production-safe; path rewrites do not establish deployment correctness.

## Deployment contract follow-up

- Added `values-staging.yaml` using the schema consumed by the current chart.
- Rebuilt `values-prod.yaml` from the chart schema rather than the stale `image.backend.tag` structure.
- Updated the backend HPA template to read `backend.autoscaling`, matching the values files.
- The duplicate backend-only staging workflow has since been removed; the full-stack staging workflow is the single staging deployment path.
- These changes have static validation only; Helm rendering and cluster behavior remain unverified because Helm/Kubernetes tooling is unavailable in this environment.


## Build and Helm contract follow-up

- Added production multi-stage Dockerfiles for the Go API and Flutter web consumer, plus an unprivileged Nginx config for the web app.
- Aligned the API's 396 local Go import references with the `nidaw-backend` module path declared in `services/api/go.mod`.
- Added staging values, rebuilt production values against the chart's actual value schema, fixed backend HPA value paths, added default frontend keys consumed by templates, and mapped ingress hosts to the backend/frontend Services.
- Aligned backend pod environment variables with the configuration loader (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSLMODE`, `JWT_SECRET`, `KAFKA_BROKERS`, and `REDIS_URL`). Deployments expect an externally managed Kubernetes Secret with keys `db-password`, `jwt-secret`, `kafka-brokers`, and `redis-url`.
- The Flutter web image compiles API URLs at build time. Helm environment variables cannot change those compiled values; build arguments are the authoritative release-time setting. Confirm that the app actually consumes the corresponding `--dart-define` values before production use.
- The full-stack staging workflow is the only staging deployment path; the production release workflow is intentionally fail-closed.
- Docker builds, Go tests, Flutter dependency resolution, and Helm rendering were not run locally because the required toolchains/dependencies are unavailable. Production readiness remains unverified.
- Fixed the named `development` build targets used by the Compose development override. Staging frontend image builds now receive staging API/WebSocket compile-time arguments.

- Backend production image now uses repository-root build context and contains `migrate-up.sh`, PostgreSQL client tooling, and versioned SQL migrations. Staging deployment invokes that real script instead of the nonexistent `/app/server migrate` CLI.
- Production release remains intentionally fail-closed at validation until migration ordering, backward compatibility, and rollback behavior are reviewed; the workflow does not publish images or mutate the production cluster while that guard is active.

- Removed the duplicate backend-only deployment workflow because it created a second staging Helm release with stale image/rollout assumptions. The full staging workflow is the single staging deployment path.
- Corrected the production preflight to reflect that backend and consumer Dockerfiles now exist. Production remains blocked specifically on the missing driver workload and the unreviewed migration ordering/rollback contract.
- Kubernetes DB host is now a required deployment input instead of an invented cluster DNS name; staging deployment must supply `STAGING_DB_HOST`, and production would require `PRODUCTION_DB_HOST` after its guard is lifted.

- Added a conditional Helm pre-install/pre-upgrade migration Job for staging so a migration failure blocks the workload update. Production keeps this hook disabled pending explicit migration review.
- Migration selection now skips development seed data outside dev/staging/test/CI and skips the T5 fault-injection table outside test/CI; fixed the migration counter loop to run in the parent shell. The broader SQL sequence still requires PostgreSQL-backed integration validation, especially around migration 015/016.

## Phase 5 — payment idempotency hardening

- Required a non-blank, at-most-255-character idempotency key in the payment command and normalized surrounding whitespace.
- Added conflict detection so the same key cannot silently replay a transaction for a different user/order/amount/currency/payment method; HTTP returns 409 for a conflicting replay.
- Copied request metadata before adding the key to avoid mutating caller-owned maps.
- Added focused unit tests. Targeted Go tests could not compile in this environment because dependencies are not cached and network access is unavailable.
- Documented that payment success events are not yet transactionally persisted in a payment outbox; delivery is not guaranteed after a publish failure.
