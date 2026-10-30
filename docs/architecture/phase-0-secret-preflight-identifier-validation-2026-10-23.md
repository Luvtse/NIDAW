# Phase 0 — Kubernetes Secret preflight identifier validation

**Date:** 2026-10-23

## Change

The external Secret preflight now validates all resource identifiers before invoking `kubectl`:

- Namespace must be a lowercase RFC 1123 DNS label of at most 63 characters.
- Backend and optional TLS Secret names must be valid lowercase DNS-subdomain names, with valid labels and a maximum length of 253 characters.
- Invalid values fail with a safe error and return code 2; no Kubernetes command is invoked.

This keeps the preflight from relying on permissive CLI argument interpretation and rejects malformed Kubernetes names before making a request. Secret values remain absent from success and failure messages.

## Regression coverage

Extended `scripts/audit/test-kubernetes-secret-preflight.py` with fake-kubectl cases for malformed namespace, backend Secret, and TLS Secret names. Each case verifies that `kubectl` was not invoked. Existing success, missing-key, TLS-type, no-cluster-scoped-Namespace-query, and secret-value-redaction cases remain.

## Validation

Passed:

- Secret preflight regression (including new malformed-identifier cases).
- Helm deployment contract.
- Deployment source-of-truth audit.
- Frontend workload evidence audit.
- Kubernetes overlay contract (it reports known missing frontend resources/files as blockers).
- Kong upstream path contract and exposure matrix regression.
- Five migration shell regressions and driver WebSocket configuration regression.

These are static or mocked checks. No real cluster, actual Secret, IAM role, Helm render, image build, or PostgreSQL instance was accessed by this change.

## Remaining Phase 0 blockers

- Verify the CI deployment identity's effective namespaced Secret `get` permissions in staging without granting broad list/watch/cluster-wide access.
- Render Helm using the repository's pinned version and perform a staging smoke test.
- Decide whether Kustomize is a supported deployment path; if so, fix missing frontend Deployment references and environment files and render all overlays.
- Complete production SQL migration ordering, backward-compatibility, and rollback review. The production release guard remains fail-closed.

**Phase 0 remains open.**
