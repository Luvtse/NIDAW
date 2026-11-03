# Deployment Architecture

## Repository deployment assets

- Local container infrastructure: `platform/docker/compose/base.yaml`, `dev.yaml`, `prod.yaml`, `monitoring.yaml`, `analytics.yaml`.
- API and app container definitions: `services/api/Dockerfile`, `apps/consumer_app/Dockerfile`, `apps/driver_app/Dockerfile`.
- Gateway configuration: `platform/gateway/`.
- Kubernetes base/overlays: `platform/kubernetes/`.
- Helm chart: `platform/helm/nidaw/`.
- Terraform environments/modules: `infrastructure/`.
- Deployment entry point: `scripts/deploy.sh`.

## Current deployment status

The local Compose development stack is the supported repository-defined developer environment. The production deployment path is not approved for rollout. `scripts/deploy.sh` deliberately exits with a blocked status and performs no infrastructure or application deployment because the Helm chart lacks a driver workload and SQL migration ordering/backward-compatibility/rollback are not approved for production.

Do not interpret the existence of Terraform, Kubernetes manifests or Helm templates as production deployment readiness.

## Environment separation

Development, staging and production must use separate credentials, databases, storage, Kafka clusters/topics, JWT signing secrets and provider accounts. Production database connections must use verified TLS. Production secrets must come from a secret manager or protected deployment secret store, not committed `.env` files or mobile build arguments.

## Network and edge

Kong configuration and route declarations are under `platform/gateway`. Verify that each upstream path and method resolves to a mounted API handler before enabling exposure. Public routes must have explicit rate limits, authentication decisions, CORS policy and request-size limits.

## Rollout requirements before production

- complete and review API, consumer and driver workloads in the chart;
- verify immutable image tags and reproducible builds;
- approve ordered migrations, expand/contract compatibility and rollback strategy;
- verify secrets, TLS, network policy and least-privilege service accounts;
- test health/readiness probes and graceful shutdown;
- run staging smoke, integration and failure-recovery checks;
- verify backups and restore procedures;
- approve a monitored rollout and a tested rollback path.
