# Phase 0 — Frontend Workload Source Reconciliation

**Date:** 2026-10-23  
**Scope:** Determine whether the existing repository supports a safe, evidence-based Kubernetes frontend Deployment definition.

## Finding

The Kubernetes overlays refer to a Deployment named `nidaw-frontend`, patch its pod resources and replica count, set the `nidaw/frontend` image tag, and generate environment-specific Nginx ConfigMaps. The Kubernetes base, however, contains only a `nidaw-frontend` Service; it has no frontend Deployment.

The current evidence supports a likely consumer-web workload for the generic Compose `frontend` service in development, but it does not support treating `nidaw-frontend` as a deployment of every client application.

## Repository evidence

- `platform/docker/compose/dev.yaml` builds the Compose `frontend` service from `../../../apps/consumer_app` using `Dockerfile.dev`.
- `apps/consumer_app/Dockerfile` builds the Flutter consumer web app and bakes `API_BASE_URL`, `WS_BASE_URL`, and `ENVIRONMENT` into the app via `--dart-define`; its Nginx config is copied into the image.
- `apps/driver_app/Dockerfile` is a separate Flutter web build with its own Nginx config.
- `apps/admin_console/package.json` defines a Vite/React build, but no `apps/admin_console/Dockerfile` exists in the inspected repository.
- `platform/docker/compose/prod.yaml` refers to the generic image `nidaw/frontend:latest`, without a corresponding in-repository image build declaration in that file.
- The Kubernetes base defines `nidaw-frontend` as a Service but no matching Deployment.
- All three overlays patch and set replicas for `nidaw-frontend`; production HPA targets `prod-nidaw-frontend` and its PDB selects frontend labels.
- The overlays' `configMapGenerator` entries create Nginx config maps from missing `nginx-dev.conf`, `nginx-staging.conf`, and `nginx-prod.conf` files. No existing frontend Deployment mounts these generated ConfigMaps.
- Staging generates a Secret from a missing `.env.staging` file. The consumer app's API configuration is build-time `--dart-define` data, not a reason to create a Secret containing frontend configuration.

## Decision for this audit

Do **not** invent a multi-client frontend Deployment or fabricate environment files. Preserve the current overlay blockers and require an explicit deployment contract that answers:

1. Is `nidaw-frontend` specifically the consumer Flutter web app, or is it intended to be a different portal?
2. Which independently deployable workloads are required for the driver Flutter web app and the React admin console?
3. Are API/WebSocket endpoints injected at image-build time, or is a supported runtime configuration mechanism required?
4. Which image build/publish workflow supplies immutable image tags for each environment?
5. Is staging frontend configuration public build-time configuration? If so, remove Secret generation; if any actual credentials are needed, keep them server-side and use the approved secret-management mechanism.

## Validation and limits

Static source inspection and a regression script verify the evidence above. This does not prove image builds, Kustomize rendering, or runtime behavior. `kustomize build` and cluster validation remain unrun because the required tools/runtime are unavailable in this environment.

**Phase 0 remains open.** The frontend Deployment, overlay input files, external secret strategy, rendered references, and live service endpoints remain acceptance blockers.
