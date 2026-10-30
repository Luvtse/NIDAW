# Phase 0 — production security scanner provisioning (2026-10-23)

## Change

The production validation workflow previously invoked `trivy` and `gitleaks` as shell commands without installing either executable. That made scanner availability depend on the runner image. Replace those implicit CLI assumptions with the official Trivy GitHub Action, which provisions Trivy as part of the action. Configure filesystem scanning explicitly for vulnerability, misconfiguration, and secret findings, with `CRITICAL,HIGH` severity and a non-zero exit code on findings.

This consolidates the intended repository security scan into one provisioned scanner; it does not claim parity with every Gitleaks-specific rule or configuration. Reintroduce Gitleaks separately only if a project-specific rule/configuration or coverage requirement calls for it and its installation/version is made explicit.

## Guardrails

- The scan remains part of the `validate` job.
- The production migration-review gate remains fail-closed and depends on validation.
- The image-build job still requires both validation and the migration-review gate, so this change does not enable production publication or deployment.
- The workflow regression test checks scanner action, scanner types, severities, and failure behavior.

## Validation and limitations

The workflow YAML is parsed locally and the regression contract is run. The actual GitHub-hosted action, Trivy database download, and scan have not been executed in this environment. `actionlint` and a live GitHub Actions run remain outstanding.
