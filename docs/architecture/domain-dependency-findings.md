# NIDAW Domain Dependency Findings

## Status and method

Phase 0 static source inspection of the uploaded repository snapshot. Import edges below are derived from Go import paths under `services/api/internal/modules`; they are not runtime call-graph proof. Test-only imports are included in the counts, so every candidate should be reviewed before refactoring.

## Verified module footprint

| Module | Go files | Preliminary responsibility | Evidence / qualification |
|---|---:|---|---|
| `nidus` | 46 | Ride-hailing, dispatch, trip lifecycle | Domain, application, infrastructure, HTTP handlers and tests exist. |
| `ledger` | 39 | Ledger and financial posting | Domain entities/value objects, services, commands, HTTP and tests exist. |
| `notifications` | 13 | Notification delivery | HTTP and event consumer code exists. |
| `telephony` | 11 | Telephony integration | HTTP and event consumer code exists. |
| `chat` | 9 | Chat/messaging | Infrastructure adapter imports Nidus directly. |
| `payment` | 9 | Payment processing/reconciliation | Reconciliation and payment operation code exists. |
| `selfie` | 8 | Identity/selfie verification | Domain/application/infrastructure/HTTP layers exist. |
| `promotions` | 7 | Promotion rules and redemption | Domain/application/HTTP code exists. |
| `payments` | 6 | Payment-method registry | Separate module, including payment-method repository and handler tests. |
| `legal` | 5 | Legal documents/consent | HTTP/domain footprint exists. |
| `logix` | 4 | Freight/shipment capability | Shipment entity, load matching and customs service only in the inspected module. |
| `analytics` | 2 | Analytics | Small Go footprint; operational completeness not established. |
| `auth` | 2 | Authentication endpoints | Exists alongside `identity` and shared auth packages. |
| `autonomous` | 2 | Autonomous capability | Purpose and production role need verification. |
| `corpus` | 2 | Corporate travel | Corporate account entity and create-booking command. |
| `identity` | 1 | Identity integration/model | Distinct module; overlap with auth needs explicit ownership. |
| `pricing` | 1 | Pricing | Small Go footprint; Nidus also contains product-specific pricing. |
| `driver-onboarding` | 1 | Driver onboarding | Small Go footprint; route/runtime wiring not yet proven. |

## Cross-module import edges

Static import scan found these cross-module edges (counts are Go source files containing the edge; test files are included):

| Source | Target | Files | Initial assessment |
|---|---|---:|---|
| `chat` | `nidus` | 1 | Candidate violation: chat adapter is coupled to ride-hailing internals. Replace with a chat-owned port or published contract if this integration is required. |
| `ledger` | `nidus` | 1 | Candidate violation: event adapter couples financial module to Nidus. Prefer a stable event contract or ledger-owned application port. |
| `nidus` | `ledger` | 3 | Candidate violation: Nidus HTTP handlers import ledger internals. Cross-domain financial effects should be behind a port/contract, not handler-level private imports. |
| `nidus` | `payments` | 3 | Candidate violation: Nidus router imports payment-method application/HTTP packages. Compose capabilities at the composition root or depend on an explicit interface. |
| `nidus` | `promotions` | 3 | Candidate violation: Nidus router imports promotion domain/HTTP packages. Avoid product router composing another module's private HTTP handlers. |
| composition root (`cmd/server`) | `auth`, `chat`, `ledger`, `legal`, `nidus`, `notifications`, `payments`, `promotions`, `selfie`, `telephony` | varies | Expected composition-root wiring; should remain the explicit place where modules are assembled. |

No import edge was detected from Corpus to Nidus/Haven/Vorax/Logix internal packages in the current Go source. This does **not** prove Corpus has safe orchestration: its booking command directly queries corporate tables and publishes topic-based events, so event contracts, publisher errors, transactional consistency, and consumer existence must be verified.

## Structural observations

1. `payment` and `payments` are distinct modules, not simply a duplicate directory. The inspected code suggests `payment` includes transaction/reconciliation/refund behavior while `payments` includes payment-method registry behavior. Consolidation or renaming is not justified until all routes, tables, consumers, provider adapters, and tests are mapped.
2. `auth`, `identity`, and `services/api/internal/shared/auth` overlap in naming and require responsibility separation; do not merge solely by name.
3. `nidus/interfaces/http/router.go` imports payment and promotion HTTP handler packages, creating a presentation-layer dependency across modules. This is a high-priority boundary cleanup candidate after baseline.
4. Shared event bus code supports Kafka and in-memory implementations, but a bus abstraction alone does not prove reliable publication, outbox semantics, or idempotent consumption.
5. The current composition root is `services/api/cmd/server/main.go`; it contains a large amount of wiring and should be refactored only after all current startup behavior and configuration are captured.

## Recommended boundary rules

- Domain/application packages must not import another product's `internal/modules/<other>/...` implementation packages.
- Shared infrastructure may expose technical abstractions, but must not own product business rules.
- Cross-domain synchronous calls use consumer-owned interfaces implemented by adapters at composition time.
- Cross-domain asynchronous communication uses versioned event contracts and explicit consumer registration.
- HTTP routers should register their own routes; the composition root or a dedicated API assembly layer mounts routers.
- Enforce the rules with a static architecture test that parses Go imports and fails on unapproved cross-module edges. Keep an explicit allowlist only where a reviewed exception is necessary.
