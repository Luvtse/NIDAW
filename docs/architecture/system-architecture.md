# System Architecture

## Current architecture

NIDAW is currently deployed from one Go API process organized as a modular monolith. Product and shared-capability modules live under `services/api/internal/modules`; shared technical infrastructure lives under `services/api/internal/shared`. The repository does not currently represent five independently deployable product microservices.

| Layer | Current implementation | Evidence location |
|---|---|---|
| API runtime | Go 1.19 module; Chi HTTP router | `services/api/go.mod`, `services/api/cmd/server/main.go` |
| Consumer client | Flutter/Dart | `apps/consumer_app` |
| Driver client | Flutter/Dart | `apps/driver_app` |
| Admin client | React + TypeScript + Vite | `apps/admin_console/package.json` |
| Relational persistence | PostgreSQL through shared database package | `services/api/internal/shared/database`, `data/migrations/postgres` |
| Cache/state | Redis integration and Compose service | `services/api/internal/shared/cache`, `platform/docker/compose/base.yaml` |
| Messaging | Kafka event bus integration | `services/api/internal/shared/eventbus` |
| Gateway | Kong configuration and route declarations | `platform/gateway` |
| Infrastructure definitions | Terraform, Kubernetes manifests, Helm chart | `infrastructure`, `platform/kubernetes`, `platform/helm` |

## Runtime composition

`services/api/cmd/server/main.go` is the composition root. It loads configuration, initializes PostgreSQL, Kafka, authentication and shared services, then mounts available HTTP handlers. Keep dependency construction at this boundary; avoid creating hidden global dependencies in product packages.

The current module tree includes Nidus, Haven, Vorax, Logix, Corpus, identity/authentication, payment/payments, ledger, pricing, promotions, notifications, chat, telephony, selfie and other supporting modules. Module directory presence alone does not prove that a module is exposed through a public API or is production-ready.

## Architectural rules

- Keep the backend modular monolith until there is an evidenced operational reason to extract a service.
- Product domains own their business state and lifecycle.
- Shared capabilities expose narrow interfaces; they must not absorb product-specific business decisions.
- Cross-product orchestration uses explicit ports and versioned contracts/events, not private table access or internal package coupling.
- Corpus must not own Nidus, Haven, Vorax or Logix internal state.
- Database writes and event publication that must be atomic require an outbox or equivalent durable pattern and idempotent consumers.
- Infrastructure adapters depend inward on application/domain contracts.
- Do not create empty service directories as placeholders for future extraction.

## Important implementation caveats

- The repository contains both `payment` and `payments` module directories; ownership and canonical usage must be resolved before further expansion.
- Logix has domain/application/infrastructure code but no Logix HTTP router mounted in the current server composition.
- Some documents and configuration files describe broader infrastructure than the running local Compose stack. Treat checked-in executable configuration and runtime wiring as authoritative.
- Kafka, TimescaleDB, MLflow, MinIO and monitoring services are present in infrastructure/configuration to varying degrees; their presence does not prove that every product workflow uses them.

## Change control

For architecture changes, update this document, the domain ownership document, database ownership and the affected API/event contracts together. Add an architecture decision record only when a durable decision cannot be expressed in these maintained references; do not create phase reports.
