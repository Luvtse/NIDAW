# Phase 0 — Secret Preflight Least-Privilege Review

**Date:** 2026-10-23

## Change

Updated `scripts/deploy/preflight-kubernetes-secrets.py` so it no longer issues `kubectl get namespace`. The namespaced `kubectl get secret ... --namespace <target>` calls prove the relevant dependency is visible to the CI identity and fail closed if the namespace or Secret is absent/inaccessible. The preflight therefore does not require cluster-scoped `get namespaces` permission.

The check still verifies the backend Secret type and required keys, and optionally verifies the TLS Secret type and required keys. Secret values are not emitted.

## Regression coverage

Updated `scripts/audit/test-kubernetes-secret-preflight.py` so the fake `kubectl` explicitly fails if the preflight tries to query a Namespace object. The test also covers valid backend/TLS Secret metadata, missing backend keys, wrong TLS Secret type, and absence of sentinel secret values in output.

## Limits

This is a local mocked test, not a live RBAC check. The actual CI identity's namespaced Secret read permissions, Secret existence, and key contents remain unverified against a cluster. The production migration-review gate remains unchanged and fail-closed. Helm rendering and cluster deployment tests remain outstanding.
