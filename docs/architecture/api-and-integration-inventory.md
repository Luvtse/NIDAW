# NIDAW API and Integration Inventory (Preliminary)

## Verified API surfaces

- Go HTTP server composition: `services/api/cmd/server/main.go` using Chi.
- Nidus HTTP router: `services/api/internal/modules/nidus/interfaces/http/router.go` and handler package.
- Ledger HTTP router: `services/api/internal/modules/ledger/interfaces/http/router.go`, mounted under `/api/v1/ledger` in the composition root.
- Auth HTTP router: mounted from the composition root.
- Notification, chat, telephony and other module HTTP handlers exist; complete registration/route inventory still needs systematic extraction.
- OpenAPI file: `services/api/api/openapi.yaml`.
- Kong route definitions include Nidus, Haven and Vorax route files; `platform/gateway/kong/kong.yml` defines `haven-service` and `vorax-service` upstreams.
- Haven and Vorax Kong routes are configured, but this repository snapshot does not contain `services/api/internal/modules/haven` or `services/api/internal/modules/vorax`. The upstream target definitions must be compared with active Compose/Kubernetes deployments to determine whether another implementation exists or the gateway routes are stale.

## Cross-product and shared integrations

| Integration | Current evidence | Risk / follow-up |
|---|---|---|
| Nidus → Payments | Nidus router imports `modules/payments` application/HTTP packages; `main.go` imports `payments` | Move wiring out of Nidus router and expose a consumer-owned port or application interface. |
| Nidus → Promotions | Nidus router imports promotion domain/HTTP packages | Use explicit application integration; avoid mounting another module's handlers from Nidus. |
| Nidus → Ledger | Nidus handler imports ledger internals in several files | Use a narrow payment/ledger port or event contract. Confirm financial side effects are idempotent. |
| Ledger → Nidus | Ledger event adapter imports Nidus | Replace with event contract / adapter to avoid reverse implementation dependency. |
| Chat → Nidus | Chat infrastructure adapter imports Nidus | Determine whether this is ride-specific chat or generic messaging; use explicit interface. |
| Corpus → product workflows | Corpus command publishes topics such as `nidus.rides`, `haven.bookings`, `vorax.orders`, `logix.shipments` | Verify subscribers, event schema, error handling, transaction/outbox, idempotency, and workflow status tracking. |
| Payments providers | Shared integration package and payment modules exist | Inventory provider callback routes, signature validation, idempotency and reconciliation. |
| Event bus | `services/api/internal/shared/eventbus` includes Kafka and in-memory implementations | Confirm production transport selection and durability semantics; in-memory behavior must not be mistaken for durable messaging. |

## Contract gaps to close

1. Generate a complete method/path list from every registered Chi router and compare it with OpenAPI and Kong routes.
2. For each route, identify auth middleware, required role, resource-level ownership checks, payload validation, timeout/rate-limit policy, and consumers in Flutter/admin.
3. Verify gateway service targets and health checks against actual runtime definitions. Gateway configuration alone does not prove the upstream is deployed.
4. Define versioned event envelopes and payload schemas for Corpus and all downstream consumers. Do not infer schemas solely from `map[string]interface{}` payloads.
5. Document provider callback authentication, replay protection, deduplication, and financial reconciliation behavior.
6. Establish contract tests for mobile/admin clients before moving endpoint paths or changing response payloads.

## Runtime reachability check

The import list at the top of `services/api/cmd/server/main.go` and router mounts in that composition root were inspected. The current executable composition imports and mounts Nidus, auth, legal/consent, ledger (feature-flagged), chat, notifications, selfie, telephony and the payment-method registry. It does not import or mount the Corpus or Logix modules in the inspected composition root. The `payment` transaction-processing HTTP handler package also is not imported there, although `payments` is imported for payment-method registry behavior.

This means the source footprint for Corpus and Logix is not evidence that their HTTP workflows are reachable through the current Go server. Their existing code may be invoked elsewhere or remain library-only, but no such runtime wiring was found in the inspected entry point. Haven/Vorax have gateway upstream definitions but no corresponding Go modules in `services/api/internal/modules/`. Before implementation claims are made, verify all active runtime targets and deployment manifests.
