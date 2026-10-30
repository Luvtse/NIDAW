# Phase 0 — Kubernetes base and overlay renderability audit

Date: 2026-10-22

## Scope and method

Static inspection of `platform/kubernetes/base` and the `dev`, `staging`, and `production` Kustomize overlays. The environment does not have `kustomize` or `kubectl`, so this report does not claim a real Kustomize build or cluster validation.

## Corrected in this pass

- Added `platform/kubernetes/base/kustomization.yaml` to declare the five existing base resource files.
- Corrected the backend Service selector to `app: nidaw` and `component: backend`, matching the backend Deployment pod-template labels.
- Added a named Service port `8080 -> 8080` for the configured Kong upstream while retaining `80 -> 8080` for the existing Ingress contract. Metrics and gRPC Service ports are unchanged.
- Added `scripts/audit/test-kubernetes-overlay-contract.py` to verify the base resource list, selector-to-pod-label compatibility, the two HTTP port contracts, and known overlay blockers.

## Confirmed blockers to rendering all overlays

The overlays are not yet independently renderable from the repository as checked in:

1. `platform/kubernetes/base` had no Kustomization file; now corrected.
2. The `dev` overlay references `nginx-dev.conf`, which is absent, and patches/scales `nidaw-frontend`, but no frontend Deployment exists in the base resources.
3. The `staging` overlay references absent `nginx-staging.conf` and `.env.staging` files under its own overlay directory; it also patches/scales the absent frontend Deployment.
4. The `production` overlay references absent `nginx-prod.conf` and patches/scales the absent frontend Deployment.
5. Production HPA targets `prod-nidaw-frontend`; its correctness cannot be established until the frontend Deployment and Kustomize name transformation are resolved.
6. The base manifests hard-code namespace values in several resources while overlays set environment namespaces and prefixes. Rendered output must be inspected before deciding how to normalize these consistently.

The repository does contain general Nginx configuration and `config/environments/staging.env`, but those are not the paths currently referenced by the overlays. The staging environment file also contains secret placeholders and should not be silently turned into a Kubernetes Secret containing literal placeholder values.

## Validation

- Python/PyYAML static contract regression passed.
- The regression reports the missing frontend Deployment and missing overlay input files rather than claiming the overlays render.
- A full Kustomize build was not run because `kustomize` and `kubectl` are unavailable.
- No frontend Deployment was invented, and no placeholder secret or environment-specific Nginx configuration was generated.

## Acceptance status

Phase 0 remains open. Next actions: decide the canonical frontend workload source (or explicitly retire the Kubernetes frontend Service/overlays), provide reviewed environment-specific Nginx configuration inputs, use an external Secret reference rather than placeholder secret generation, normalize namespaces/prefixes, then run `kustomize build` for all three overlays and validate rendered resource references.
