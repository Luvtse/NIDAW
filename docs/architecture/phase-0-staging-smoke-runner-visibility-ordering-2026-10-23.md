# Phase 0 — Staging Smoke-Test Runner Visibility Ordering

Date: 2026-10-23

## Finding

The staging `smoke-tests` job previously ran checkout and the first smoke-test script before invoking `step-security/harden-runner`. This ordering meant network visibility/audit configuration was not established for those earlier steps.

## Change

Moved `step-security/harden-runner@v2` to the first step of `smoke-tests`, retaining `egress-policy: audit`. Added a regression assertion to `scripts/audit/test-github-workflow-step-contract.py` that checks the action is first and that the audit policy remains configured.

## Validation

The YAML parsing and static workflow contract test pass locally. No GitHub-hosted workflow was run; actual runner telemetry and observed egress remain unverified. This change is audit-only and does not itself block egress.

## Remaining work

- Execute the staging workflow and inspect the harden-runner audit output.
- Decide whether the job needs an enforced egress allowlist; do not switch from audit to block mode until all required endpoints are identified and validated.
- Continue Phase 0 acceptance checks; production remains blocked by the migration-review gate.
