# Phase 0 — External Kubernetes Secret preflight

**Date:** 2026-10-23  
**Scope:** Add a fail-closed deployment preflight for externally managed backend and TLS Secrets without disclosing secret material.

## Implementation

Added `scripts/deploy/preflight-kubernetes-secrets.py`. It uses `kubectl get ... -o json` and validates only metadata, Secret type, and presence of expected keys. It never prints Secret values or raw `kubectl` errors.

- Target namespace must be readable and match the requested namespace.
- The backend Secret defaults to `nidaw-backend-secrets`, must be `Opaque`, and must contain non-empty `db-password`, `jwt-secret`, `kafka-brokers`, and `redis-url` data entries.
- An optional TLS Secret (production uses `nidaw-tls`) must be type `kubernetes.io/tls` and contain non-empty `tls.crt` and `tls.key` entries.
- Missing resources, missing keys, incorrect types, invalid output, timeout, and unavailable `kubectl` fail closed with non-sensitive diagnostics.

## Workflow integration

- Staging runs the preflight after configuring cluster credentials and before Helm upgrade.
- Production canary and full-deployment jobs include the same preflight before Helm changes. The earlier production validation guard still exits before these jobs can run; this change does not bypass or weaken that guard.

## Tests

`scripts/audit/test-kubernetes-secret-preflight.py` runs against a temporary fake `kubectl`, not a real cluster. It covers success, missing backend keys, and wrong TLS type. Sentinel values are asserted absent from stdout/stderr.

The preflight test and existing Helm, deployment source-of-truth, frontend evidence, Kubernetes overlay, Kong path, and Python syntax checks passed locally.

## Limitations and acceptance items

No cluster was queried; no real Secret values were accessed. This does not prove that staging or production Secrets exist, are current, or are backed by the approved secret-management system. Before enabling a release, run the preflight using a least-privilege CI identity against the actual namespace and confirm required read permissions. Do not grant Secret read permissions to the application ServiceAccount for this purpose. Production remains blocked pending the migration review.

**Phase 0 remains open.**
