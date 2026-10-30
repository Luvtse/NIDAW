# Phase 0 — Helm ServiceAccount RBAC review

**Date:** 2026-10-23

## Finding

The Helm ServiceAccount template previously also created a namespaced Role and RoleBinding granting `get` and `watch` on a Secret name derived from the Helm release. The backend and migration manifests consume credentials through pod-level `secretKeyRef` fields. That mechanism does not require the application process's ServiceAccount to read Secret objects through the Kubernetes API. No in-repository application use of a Kubernetes API client for Secret retrieval was found in this audit.

The Role's release-derived `resourceNames` also did not match the external Secret contract used by the deployment preflight (`nidaw-backend-secrets`), making the grant both unnecessary for the observed workload contract and potentially ineffective for that external Secret.

## Change

The template now creates only the configured ServiceAccount. It does not create a Role or RoleBinding. This removes unnecessary application-level Secret API permissions; it does not change pod `secretKeyRef` usage.

## CI identity is separate

The deployment workflow's `kubectl get secret` preflight runs under the CI/EKS identity, not the chart's workload ServiceAccount. That CI identity needs narrowly scoped namespaced `get` access to the exact Secret resources it validates (backend Secret and, in production, TLS Secret). Do not grant `list`, `watch`, or cluster-wide Secret access just for this preflight. The actual EKS access entry/IAM mapping and effective Kubernetes RBAC have not been inspected and must be verified in the target cluster before acceptance.

## Validation and limits

- `scripts/audit/test-helm-serviceaccount-rbac.py` statically verifies that the chart ServiceAccount template does not emit RBAC Roles/Bindings and that pod-level Secret references remain.
- This is source/static validation only. Helm template rendering, Kubernetes `auth can-i` checks, and live cluster verification remain outstanding because Helm, kubectl, and cluster access are unavailable in this environment.
- Phase 0 remains open.
