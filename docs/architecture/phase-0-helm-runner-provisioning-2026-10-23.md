# Phase 0 — Explicit Helm CLI provisioning in deployment workflows

Date: 2026-10-23

## Finding

The staging and production deployment jobs invoke `helm upgrade`, `helm uninstall`, or other Helm commands, but the workflows did not explicitly install a Helm CLI. The hosted-runner image is not a reproducible toolchain contract, so relying on an unspecified preinstalled Helm version risks missing commands or version drift.

## Change

- Added `azure/setup-helm@v5.0.1` to the staging deployment job and the production canary and full-deployment jobs.
- Pinned the CLI to Helm `v3.18.4` rather than relying on the setup action's default/latest version. This is an explicit Helm 3 choice for the existing chart workflow.
- Added `helm version --short` checks immediately after setup.
- Extended `scripts/audit/test-github-workflow-step-contract.py` to require exactly one setup action, the pinned version, and verification before the first Helm invocation in each active deployment job.

## Validation

Local YAML parsing and the static workflow contract test are expected to verify step ordering and version pinning. The environment does not provide `helm` or `actionlint`, so this does not validate the downloaded binary, render the chart, or execute a GitHub-hosted workflow. Those remain runtime acceptance checks.

## Safety boundary

This change only makes the deployment CLI explicit. It does not change deployment conditions, credentials, chart values, or the production migration-review gate. The production gate remains fail-closed.
