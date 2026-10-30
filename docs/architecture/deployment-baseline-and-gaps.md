# Deployment Baseline and Gaps — Phase 0

## Current evidence

- The Compose implementation lives in `platform/docker/compose/{base,dev,prod,analytics,monitoring}.yaml`.
- Root `docker-compose.yml` is guidance-only and defines no services.
- The root Makefile's `dev` target and `scripts/setup.sh` now use the explicit base+dev Compose file pair under `platform/docker/compose/`.
- The root Makefile and `scripts/deploy.sh` previously used `driver-app`; the tracked app is `driver_app`.
- GitHub Actions include backend CI/deploy, frontend CI, staging, production, and security scan workflows. These are not yet demonstrated to represent one consistent canonical deployment path.
- Helm charts exist under `platform/helm/nidaw`; Kubernetes manifests also exist under `platform/kubernetes/`. The active production source of truth is not established.

## Verification performed

- `npm --prefix apps/admin_console run build`: **PASS** (TypeScript build and Vite production bundle).
- `bash -n scripts/migrations/migrate-up.sh`: **PASS** (syntax only).
- `bash -n scripts/migrations/migrate-down.sh`: **PASS** (syntax only).
- Docker/Compose, psql, Helm, kubectl, and Flutter are not installed in this audit environment; service and deployment validation could not run.
- Go is installed, but the earlier test attempt could not fetch uncached dependencies; no Go test pass is claimed.

## Required action before Phase 1

1. Select the canonical local development command and make it explicit in the README, Makefile, and setup scripts.
2. Decide whether Helm or raw Kubernetes manifests are authoritative for deployment; document the other as legacy or supported secondary deployment.
3. Correct path mismatches only as part of a coherent multi-file change, with corresponding CI and deployment updates.
4. Fix and test migration runner correctness before using it as a release gate.
5. Validate clean database installation and upgrade behavior in a PostgreSQL-enabled environment.
6. Do not relocate directories until all path references have been inventoried and a coordinated migration patch is ready.
- `npm run lint --prefix apps/admin_console`: **BLOCKED** because the package script invokes `eslint`, but no `eslint` executable is available in the installed `apps/admin_console/node_modules/.bin`. This may reflect an undeclared/missing dependency or an incomplete dependency installation; inspect the manifest and lockfile before deciding whether to add or install it.

## Phase 1 follow-up after core application moves

The primary app directories are now `services/api`, `apps/consumer_app`, `apps/driver_app`, and `apps/admin_console`; path references in workflows, Compose dev build contexts, scripts, editor config, and docs were updated. Static old-path scan passed. The admin production build passed after the move using the dependency tree supplied in the original archive.

The static Compose path scan now resolves the checked-in file/directory mounts for base, dev, prod, monitoring, and devcontainer configs. A Feast Dockerfile has now been added and the analytics Compose mount was aligned with the image contents. The Feast dependency build and analytics runtime remain unverified because Docker is unavailable here.

The previous `scripts/deploy.sh` referenced nonexistent Terraform and chart paths and attempted to deploy images that were not pushed. It has been replaced with a fail-closed preflight using `infrastructure/environments/{dev,staging,production}` and `platform/helm/nidaw`. Backend and consumer production Dockerfiles and a migration runner now exist, but the script still refuses production planning/deployment until the driver workload is represented in Helm and production migration ordering, compatibility, and rollback are reviewed. It is not a production deployment path yet.
