# Phase 0 — Deployment Workflow Security Contract

**Date:** 2026-10-23

## Findings and changes

- Set `contents: read` as the default GitHub token permission for staging and production deployment workflows.
- Scoped `packages: write` to the staging image-build jobs and production image-build job, which push images to GHCR.
- Scoped production release creation to `contents: write` and removed token permissions from notification-only jobs.
- Changed production version validation and version output to receive the requested version through an environment variable. The version is no longer inserted directly into shell source, avoiding shell interpretation of a manually supplied version string.
- Preserved the production migration-review fail-closed guard.

## Regression

`scripts/audit/test-deployment-workflow-security-contract.py` verifies the permission boundaries, environment-variable handoff, and production guard. `scripts/audit/test-github-workflow-step-contract.py` separately verifies workflow step structure.

## Limits

These are source-level checks. The repository's effective GitHub Actions permissions, AWS IAM/EKS authorization, GHCR package settings, and live staging behavior have not been verified. Production deployment remains blocked pending migration review. Phase 0 remains open.
