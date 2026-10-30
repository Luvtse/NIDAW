# Phase 0 — Production Validation and Migration Gate Separation

**Date:** 2026-10-23

## Finding

The production workflow placed the intentional fail-closed migration review step inside the `validate` job before the full test suite and security scan. Because that step always exits nonzero, later validation steps never ran. This preserved release blocking but also prevented useful pre-release validation.

## Correction

- Moved the fail-closed step into a dedicated `production-migration-review-gate` job that depends on successful `validate`.
- Made the image `build` job depend on both `validate` and `production-migration-review-gate`.
- Kept the gate fail-closed. Until migration execution is reviewed, the gate fails and build/deployment jobs remain blocked.
- Extended `scripts/audit/test-deployment-workflow-security-contract.py` to assert the intended dependency structure and confirm the test/security steps remain in `validate`.

## Security and release behavior

The change does not approve migrations, publish images, or deploy to production. It makes tests and security scanning reachable while preserving the release block. Because the gate is an explicit failed dependency of `build`, downstream production jobs cannot proceed.

## Validation limits

Static YAML parsing and regression tests do not replace GitHub Actions validation or an actual run. The runner's availability of the `trivy` and `gitleaks` CLI tools should be verified; the workflow currently invokes them directly. Production migration ordering, backward compatibility, and rollback still require review. Phase 0 remains open.
