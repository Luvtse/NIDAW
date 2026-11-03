# Deployment Runbook

## Deployment status: blocked

The repository's `scripts/deploy.sh` is intentionally fail-closed. It checks that the selected Terraform environment and Helm chart exist, then exits with status 3 because the chart does not define a driver workload and SQL migration ordering, backward compatibility and rollback have not been approved. It performs no image push, infrastructure apply, database migration or Kubernetes mutation.

**Do not treat the presence of Terraform, Helm or Kubernetes files as permission to deploy.** Do not bypass the guard until the blockers below have been resolved and reviewed.

## Local development stack

```bash
cp env.example .env
# Set MINIO_USER and MINIO_PASSWORD and development credentials.
make setup
```

The Compose configuration is under `platform/docker/compose/`. Development uses `base.yaml` plus `dev.yaml`. Use `make clean` to stop the stack while retaining volumes.

## Pre-deployment gates

- [ ] Define and validate backend, consumer web and driver workloads in the deployment chart.
- [ ] Confirm image build contexts, immutable tags, registry permissions and provenance.
- [ ] Validate all configuration and secret references against runtime code.
- [ ] Approve SQL migration ordering, expand/contract compatibility and rollback behavior.
- [ ] Test migrations against a production-like database snapshot.
- [ ] Verify TLS, ingress/gateway paths, CORS, authentication and rate limiting.
- [ ] Verify readiness/liveness probes, resource limits and graceful shutdown.
- [ ] Verify backup freshness and a successful restore exercise.
- [ ] Deploy to staging and pass API, consumer, driver, payment and critical workflow smoke tests.
- [ ] Approve rollout, monitoring ownership and rollback decision criteria.

## Safe preflight

```bash
ENVIRONMENT=staging ./scripts/deploy.sh --check
```

This command is expected to report the current deployment blocker; it does not deploy. Do not interpret a future successful preflight as proof that application rollout is safe without separate approval.

## Rollback requirements

A rollback plan must identify the previous immutable application image, compatible database schema state, configuration/secrets version, gateway configuration and data-repair procedure. Application rollback alone is insufficient if a migration is not backward-compatible. No production rollback command is published as approved until the deployment and migration contracts are complete.

## Incident response

During a deployment incident, stop rollout, preserve logs/traces and deployment metadata, assess data integrity, and engage the service owner. Do not run destructive rollback or down-migrations without an approved recovery plan. Follow [disaster recovery](disaster-recovery.md) for data-loss or infrastructure-failure scenarios.
