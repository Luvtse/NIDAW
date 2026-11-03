# NIDAW

NIDAW is a multi-product mobility and services platform repository. The current repository is organized as a Go backend modular monolith, Flutter consumer and driver applications, and a React/TypeScript administration console.

## Products

- **Nidus** — ride-hailing. The most developed product surface in this repository.
- **Haven** — accommodation discovery and booking module.
- **Vorax** — restaurant discovery, menus and food-order module.
- **Logix** — freight/logistics domain code; its HTTP product surface is not currently mounted in the API server.
- **Corpus** — corporate booking and approval workflow module.

Product code maturity differs. See [product documentation](docs/products/README.md) for implemented repository evidence and limitations.

## Repository entry points

| Component | Location | Technology |
|---|---|---|
| API | `services/api` | Go, Chi, PostgreSQL, Redis/Kafka integrations |
| Consumer app | `apps/consumer_app` | Flutter/Dart |
| Driver app | `apps/driver_app` | Flutter/Dart |
| Admin console | `apps/admin_console` | React, TypeScript, Vite |
| Database migrations | `data/migrations` | PostgreSQL SQL |
| Docker environment | `platform/docker/compose` | Docker Compose |
| Gateway | `platform/gateway` | Kong configuration |
| Infrastructure | `infrastructure` | Terraform |

## Local development

Requirements: Docker with Compose v2, Go toolchain compatible with `services/api/go.mod`, Flutter/Dart for mobile applications, and Node.js/npm for the admin console.

```bash
cp env.example .env
# Set local DB_PASSWORD to nidaw_dev and set MINIO_USER/MINIO_PASSWORD.
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml up -d
```

Apply database migrations before seeding or relying on the API. The current `scripts/setup.sh` invokes the seed script without first applying migrations, so it is not a reliable fresh-database bootstrap. Follow [Getting started](docs/development/getting-started.md) for the safe manual order.

## Documentation

Start at [docs/README.md](docs/README.md). Operational deployment is deliberately fail-closed: `scripts/deploy.sh` currently reports a production deployment blocker and does not deploy or mutate infrastructure. See [deployment runbook](docs/operations/deployment-runbook.md).

## Validation

The repository's declared test target is `make test`. Run individual toolchain checks from the relevant application directory; consult [development guide](docs/development/development-guide.md). A successful local build or test run is not a production-readiness certification.

## License and support

See [LICENSE](LICENSE). Do not rely on placeholder contact details or external support URLs unless independently confirmed for the deployment.
