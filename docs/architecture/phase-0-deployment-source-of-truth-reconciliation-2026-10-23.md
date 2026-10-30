# Phase 0 — Deployment Source-of-Truth Reconciliation

**Date:** 2026-10-23  
**Scope:** Trace the checked-in CI/CD entry points, Helm workload templates, frontend image builds, and the parallel Kustomize overlays.

## Verified findings

1. **The checked-in CI/CD deployment path is Helm.** `.github/workflows/deploy-staging.yml` builds backend and consumer frontend images, then runs `helm upgrade --install` against `platform/helm/nidaw` with `values-staging.yaml`. It verifies Helm-named backend and frontend Deployments by rollout status.
2. **The Helm chart does define a frontend Deployment and Service.** `platform/helm/nidaw/templates/frontend-deployment.yaml` and `frontend-service.yaml` render them when `frontend.enabled` is true. Therefore the absent frontend Deployment in `platform/kubernetes/base` is a Kustomize-base/overlay gap, not evidence that the repository has no frontend workload definition at all.
3. **The current frontend image is the consumer Flutter app.** The staging and production workflows build from `apps/consumer_app` and tag the resulting image as the frontend image. The driver app and admin console have separate source/build concerns and are not deployed by these frontend image steps.
4. **Flutter API/WebSocket endpoints are build-time configuration.** `apps/consumer_app/Dockerfile` passes `API_BASE_URL`, `WS_BASE_URL`, and `ENVIRONMENT` to `flutter build web --dart-define=...`. The staging and production workflows pass matching environment-specific build arguments. Changing the Helm Deployment environment variables alone does not rewrite the compiled Flutter bundle; the corresponding image must be built with the intended values.
5. **Kustomize is a parallel, currently incomplete deployment description.** `.github/workflows/deploy-staging.yml` and `.github/workflows/deploy-prod.yml` invoke Helm, not the Kubernetes Kustomize overlays. The overlays still reference an absent frontend Deployment and missing environment-specific Nginx files, and staging references a missing `.env.staging` Secret-generator input. Do not assume those overlays are the active release path or that they render successfully.
6. **Production release is intentionally fail-closed.** `.github/workflows/deploy-prod.yml` has a validation step that exits nonzero while production migration execution review remains pending. Do not bypass or weaken this gate as part of the Kubernetes audit.

## Impact and action

- Treat Helm + the CI workflows as the evidenced staging/release source of truth until the repository owner explicitly changes that decision.
- Keep Kustomize overlay repair separate: either formally designate it as supported and make it renderable, or mark/deprecate it after owner review. Do not silently treat it as interchangeable with Helm.
- Preserve environment-specific Flutter build args and test that the image tag and values are from the same environment/release. Helm `frontend.env` values are not runtime Flutter configuration unless the application is deliberately changed to use a runtime config mechanism.
- Keep production blocked until its existing migration review gate is satisfied.
- Continue to treat driver and admin deployments as separate scope; do not bundle them into the consumer frontend image without an approved architecture decision.

## Regression coverage

`scripts/audit/test-deployment-source-of-truth.py` checks the checked-in workflow commands, build contexts/arguments, Helm frontend templates, and production fail-closed guard. It is a source-contract check, not a CI execution, image build, Helm render, or cluster test.

## Validation limits

The source-contract test and YAML parsing can be run locally. This environment does not have the required Docker, Helm, kubectl, or cluster access to validate image builds, rendered Helm output, rollout behavior, or runtime endpoint reachability.

**Phase 0 remains open.** Deployment-path ownership, actual Helm rendering, runtime/API contract tests, migration review, and live deployment validation remain outstanding.
