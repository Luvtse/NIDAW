# Phase 0 — Deployment Path and Gateway Static Validation

## Status

**Static checks completed; deployment-path acceptance remains open.** This pass inspects the current repository snapshot only. Docker Compose, Kong runtime, Kubernetes/Kustomize, Helm, and cluster connectivity were not executable in the available environment, so no live routing or deployment claim is made.

## Evidence and findings

### 1. Compose Kong upstream hostname does not match the Compose service key

- `platform/docker/compose/dev.yaml` defines the backend Compose service as `backend` (line 79) and sets `container_name: nidaw-backend-dev` (line 84).
- `platform/docker/compose/prod.yaml` defines the backend service as `backend` (line 76) and sets `container_name: nidaw-backend-prod` (line 78).
- The Kong declarative file `platform/gateway/kong/kong.yml` targets `http://nidaw-backend:8080` (for example lines 18–23), and its upstream target also uses `nidaw-backend:8080` (line 760).
- Neither Compose file declares `nidaw-backend` as a network alias. A Compose `container_name` does not create an alias with a different name.

**Impact:** In the checked-in Compose configuration, Kong's configured upstream hostname is not established by the backend service definition. Gateway requests may fail DNS resolution even though the backend container is running.

**Action:** Select and document the supported deployment topology. For Compose, use the Compose service DNS name or add an explicit network alias. For Kubernetes, configure the gateway to use the Kubernetes Service DNS name. Do not assume one hostname works in both environments.

### 2. Kubernetes backend Service selector does not match backend Pod labels

- `platform/kubernetes/base/backend-deployment.yaml` labels backend Pods with `app: nidaw` and `component: backend` (lines 17–19); its Deployment selector uses the same pair (lines 11–14).
- `platform/kubernetes/base/backend-service.yaml` selects Pods using `app.kubernetes.io/name: nidaw-backend` and `app.kubernetes.io/component: backend` (lines 22–24).
- A direct static comparison of the checked-in base manifests returns `K8S_SELECTOR_MATCHES_BASE_POD = False`.
- The inspected dev, staging, and production Kustomize overlays add an `environment` label and a name prefix; they do not rename `app` to `app.kubernetes.io/name` or otherwise reconcile these two selector keys.

**Impact:** The base Service selector cannot select the base Deployment's Pods. Unless an untracked external patch changes these labels, the Service can have no ready endpoints and traffic through that Service will fail.

**Action:** Align Deployment pod labels and Service selectors in the base manifests, then render all Kustomize overlays and assert that each Service selector matches its intended Pods. Do not hand-edit rendered resources as a substitute for correcting their source manifests.

### 3. Kong service path and route path repeat the same product prefix

- The Nidus Kong Service defines `path: /api/v1/nidus` (`platform/gateway/kong/kong.yml`, line 23).
- Its routes use paths beginning `/api/v1/nidus/...` (for example lines 32–45) and set `strip_path: false`.
- Haven and Vorax repeat the same configuration pattern with `/api/v1/haven` and `/api/v1/vorax` service paths and matching full-prefix route paths.

**Impact:** This configuration is a high-priority upstream-URI composition risk: Kong's service path and the preserved route path may combine into a duplicated prefix. Static YAML parsing alone cannot prove the exact forwarded URI for the deployed Kong version/configuration.

**Action:** Use one clear path strategy: either preserve the full client path and leave the Service path empty, or deliberately strip/rewrite the route prefix while using a Service path. Confirm the exact effective upstream URI with a Kong integration test before changing production routing.

### 4. Kubernetes Service ports and scrape annotations need reconciliation

- `platform/kubernetes/base/backend-service.yaml` exposes the HTTP Service port `80` to container port `8080` (lines 25–29), which is consistent with an ingress targeting Service port `80`.
- The same Service declares a metrics port `9090` targeting container port `9090` (lines 30–33), but its Prometheus scrape annotation says port `8080` (line 18).
- The backend Deployment manifest only declares container port `8080` (line 25); declaration alone does not prove whether the application also listens on `9090`.

**Impact:** Prometheus may scrape the wrong port, and the actual metrics listener/port contract is not established by the manifests.

**Action:** Verify the Go server's actual metrics listener and align the Service, annotations, and Prometheus target to that listener. Render manifests and verify connectivity in a cluster-enabled environment.

### 5. Helm chart is a separate deployment path and must be validated independently

The Helm chart defines its backend Service through values and templates (`platform/helm/nidaw/templates/backend-service.yaml`; default values set Service port `80` and target port `8080`). This is not evidence that the raw Kustomize manifests or Compose configuration work, nor is it proof that Helm rendering succeeds.

**Action:** Treat Compose, raw Kustomize overlays, and Helm as separate candidate deployment paths until one is explicitly selected as canonical and each retained path is independently validated.

## Static validation performed

The following files parsed successfully with PyYAML `safe_load_all`:

- `platform/docker/compose/base.yaml`
- `platform/docker/compose/dev.yaml`
- `platform/docker/compose/prod.yaml`
- `platform/gateway/kong/kong.yml`
- `platform/kubernetes/base/backend-deployment.yaml`
- `platform/kubernetes/base/backend-service.yaml`
- `platform/kubernetes/base/ingress.yaml`
- `platform/kubernetes/overlays/dev/kustomization.yaml`
- `platform/kubernetes/overlays/staging/kustomization.yaml`
- `platform/kubernetes/overlays/production/kustomization.yaml`

This establishes YAML syntax parseability for those files only. It does not validate Kong's schema, Compose interpolation/merge semantics, Kubernetes API validation, Kustomize transformation output, Helm templates, runtime DNS, readiness, or forwarded request URIs.

## Environment blockers

The following executables were unavailable: `docker`, `docker-compose`, `helm`, `kubectl`, and `flutter`. Go is present, but this deployment pass did not run Go tests or launch the application. PostgreSQL-backed migration checks and live gateway-to-backend requests remain unverified.

## Required next steps before Phase 0 acceptance

1. Choose the canonical local/integration deployment path and state whether Kong is used in Compose, Kubernetes, or both.
2. Correct the Compose upstream DNS contract and Kubernetes Service/Pod selector mismatch as a cohesive, reviewed deployment change.
3. Resolve the Kong path-prefix strategy and add route-level integration tests that assert the upstream URI.
4. Reconcile the metrics listener, Service port, and scrape configuration.
5. Render Compose configuration, Kong configuration, Kustomize overlays, and Helm templates with their supported CLIs.
6. Launch the selected topology and verify DNS, TCP connectivity, health/readiness, route-method coverage, and actual forwarded URIs.
7. Record results and any external blockers in the Phase 0 acceptance review. Do not mark Phase 0 complete until the master roadmap's remaining acceptance conditions are met.
