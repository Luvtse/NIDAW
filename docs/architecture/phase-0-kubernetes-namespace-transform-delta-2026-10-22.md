# Phase 0 — Kubernetes namespace/name-prefix reconciliation

Date: 2026-10-22

## Finding

The base contains a `Namespace` named `nidaw`, while each overlay applies a `namePrefix` and independently sets the namespace transformer value. The prior values (`nidaw-dev`, `nidaw-staging`, `nidaw-production`) did not match the namespace object names produced by the corresponding `dev-`, `staging-`, and `prod-` prefixes. In addition, the base NetworkPolicy selected the namespace by the literal name `nidaw`, which would not match environment-prefixed namespaces.

## Changes

- Align overlay namespace values to the names produced by their prefixes: `dev-nidaw`, `staging-nidaw`, and `prod-nidaw`.
- Change intra-platform NetworkPolicy namespace selectors from `kubernetes.io/metadata.name: nidaw` to the stable namespace label `app.kubernetes.io/part-of: nidaw-platform`, which is present on the base Namespace resource and is retained when the Namespace name is prefixed.
- Preserve the explicit `kube-system` namespace selector used for DNS egress.
- Extend `scripts/audit/test-kubernetes-overlay-contract.py` to guard the namespace/prefix contract and prevent hard-coded `nidaw` selectors from breaking environment-prefixed namespace isolation.

## Validation and limits

- The static Kubernetes overlay contract test passes.
- The YAML files parse successfully with PyYAML.
- `kustomize` and `kubectl` are unavailable, so the effective transformation output has not been rendered or verified with the pinned Kustomize version. This change is a static correction, not proof of deployment readiness.
- Existing overlay blockers remain: frontend Deployment is absent, environment-specific Nginx generator inputs are missing, and staging references `.env.staging`. No frontend workload or secret values were fabricated.

## Status

Phase 0 remains open pending a real `kustomize build` for all overlays and resolution of the remaining workload/configuration blockers.
