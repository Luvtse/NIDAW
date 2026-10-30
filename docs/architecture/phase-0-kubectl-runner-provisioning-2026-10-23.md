# Phase 0 — Explicit kubectl CLI provisioning in deployment workflows

Date: 2026-10-23

## Finding

The staging deployment, production canary, and full production deployment invoke `kubectl` after configuring AWS/EKS access, but they did not explicitly install a Kubernetes client. Relying on whatever happens to be present on `ubuntu-latest` leaves the deployment CLI version outside the repository's toolchain contract.

## Change

- Added `azure/setup-kubectl@v4` to the staging deployment and both production deployment jobs.
- After AWS credentials are configured, each job asks EKS for the target cluster's Kubernetes minor version.
- The workflow resolves the latest published `kubectl` patch for that same minor version from the official Kubernetes release endpoint, validates the returned version format/minor, and passes it to the setup action.
- Added an explicit client-version verification step before updating kubeconfig or running Kubernetes-dependent preflight/deployment commands.
- Extended `scripts/audit/test-github-workflow-step-contract.py` to enforce resolver, setup, verification, and ordering in all three deployment jobs.

The version is resolved per target cluster rather than hard-coding a guessed Kubernetes minor version. The resolver fails closed if EKS version lookup fails, the response is malformed, or a compatible stable release cannot be resolved.

## Validation

- All five workflow YAML files parse with PyYAML.
- `scripts/audit/test-github-workflow-step-contract.py` passes and checks the explicit Helm and kubectl provisioning contracts.
- `scripts/audit/test-deployment-workflow-security-contract.py` passes; the production migration-review gate remains fail-closed.
- `scripts/audit/test-deployment-source-of-truth.py` passes.
- The shell regular expression used to verify the returned `kubectl` version was exercised with a representative `1.33` / `v1.33.5` pair.

The environment does not provide `kubectl`, `helm`, or `actionlint`; no GitHub-hosted workflow was run, no live EKS cluster was queried, and no chart render or cluster operation was performed. This is static validation, not evidence of deployment readiness.

## Safety boundary

This change provisions the client tool only. It does not alter AWS permissions, cluster configuration, chart values, migration execution, or deployment conditions. The production migration-review gate remains fail-closed.

## External reference

The official Azure/setup-kubectl action documents the `version` input for selecting a specific `kubectl` binary: https://github.com/Azure/setup-kubectl
