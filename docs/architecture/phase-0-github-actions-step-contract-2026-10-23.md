# Phase 0 — GitHub Actions Step Contract

**Date:** 2026-10-23

## Finding

The staging deployment workflow's API smoke-test step declared both `uses: step-security/harden-runner@v2` and `run:`, which is invalid GitHub Actions step structure. A step must use an action or execute a shell script, not both.

## Correction

Split the step into:
1. `Harden runner network visibility`, which invokes `step-security/harden-runner@v2` with `egress-policy: audit`.
2. `Run API tests`, which runs the health and readiness HTTP checks using curl's explicit fail/silent/show-error flags.

The checks and target URLs are preserved. This is a workflow syntax correction; it does not establish that staging is reachable or healthy.

## Regression

`scripts/audit/test-github-workflow-step-contract.py` parses all `.github/workflows/*.yml` files and asserts each step declares exactly one of `uses` or `run`.

## Validation limits

Static YAML and workflow-structure checks do not substitute for GitHub Actions workflow validation or a real staging run. CI credentials, cluster access, and production migration review remain unverified. Phase 0 remains open.
