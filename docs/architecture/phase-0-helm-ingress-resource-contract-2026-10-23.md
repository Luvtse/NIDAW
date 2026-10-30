# Phase 0 — Helm ingress and resource contract audit

**Date:** 2026-10-23
**Scope:** Static validation of Helm environment values against ingress path handling, frontend container ports/probes, resource requests/limits, and production safety guards.

## Findings corrected

1. **Ingress rewrite annotation removed from dev, staging, and production values.** The chart uses root (`/`) Prefix paths for the API and SPA hosts; the global `nginx.ingress.kubernetes.io/rewrite-target: /` annotation would rewrite requests to `/` and can break API paths and client-side asset/routing behavior. Development's `/api` prefix is now forwarded without that global rewrite.
2. **Production backend memory limit corrected from `1Gi` to `3Gi`.** Its existing memory request was `2Gi`, which exceeded the limit and violates Kubernetes container resource constraints. The 3Gi limit preserves the 2Gi request and allows bounded headroom.
3. **Added `scripts/audit/test-helm-deployment-contract.py`.** It checks ingress rewrite invariants for all three environments, request/limit ordering, frontend Nginx port alignment, frontend health/readiness probe paths, and retention of the production fail-closed migration review guard.
4. **Updated `docs/architecture/phase-checklist.md`** with this validation and outstanding runtime checks.

## Validation

- Helm deployment contract regression: PASS.
- Deployment source-of-truth regression: PASS.
- Kubernetes frontend workload evidence regression: PASS.
- Kubernetes overlay contract regression: PASS; expected missing frontend Deployment and overlay inputs remain explicitly reported.
- Kong upstream path contract regression: PASS.
- YAML parsing: PASS for 21 Helm, Kubernetes, and Compose YAML files.
- Existing migration runner, rollback, payment preflight, driver WebSocket, and Kong route/exposure regression scripts are part of the continuation validation set.

## Limits and remaining acceptance work

`helm` is unavailable in this environment, so `helm lint`/`helm template` and live Kubernetes checks were not run. This is static source validation only. External secret provisioning, chart resource names/selectors, TLS secret existence, runtime image build/pull, database connectivity, migration ordering/rollback, and ingress behavior still need environment-backed verification. The production deployment workflow's migration-review guard remains intact; this pass does not authorize production release.

**Phase 0 remains open.**
