# Domain Boundaries

## Product ownership

| Domain | Business responsibility | Current repository evidence | Exposure/maturity note |
|---|---|---|---|
| Nidus | Ride request, dispatch, matching, trip lifecycle, driver/rider ride operations | `internal/modules/nidus` | Richest API and client surface; routes mounted in API |
| Haven | Hotel catalog, room inventory and accommodation bookings | `internal/modules/haven` | HTTP routes mounted; booking/catalog services and persistence adapters exist |
| Vorax | Restaurant catalog, menus, orders and order tracking | `internal/modules/vorax` | HTTP routes mounted; core order/catalog services exist |
| Logix | Shipment, carrier, customs and load-matching domain | `internal/modules/logix` | Domain and persistence code exist; no Logix HTTP router mounted in server composition |
| Corpus | Corporate booking request and approval/rejection workflow | `internal/modules/corpus` | HTTP routes mounted for corporate bookings; orchestration breadth must not be overstated |

## Shared capabilities

- **Identity/access and authentication:** authentication primitives and authorization middleware.
- **Payments:** provider integration and payment-method capabilities; product workflows must not own provider settlement internals.
- **Ledger/finance:** accounting, financial posting, reconciliation and reporting; product lifecycle remains product-owned.
- **Pricing/promotions:** reusable pricing and promotion capabilities with explicit product inputs.
- **Notifications, chat and telephony:** delivery/communication adapters; product modules own when and why a communication is sent.
- **Platform:** configuration, database, cache, event bus, gateway and observability.

## Dependency rules

1. Product modules may depend on their own domain/application layers and approved shared contracts.
2. Product-to-product communication must cross an explicit application port, adapter or versioned event contract.
3. Corpus orchestrates product capabilities through published contracts; it must not import another product's private implementation or mutate its private tables.
4. Payments and ledger do not own ride, hotel, food-order, freight or corporate booking state transitions.
5. Shared modules must not become generic containers for product-specific rules.
6. No cyclic dependencies between product domains.

## Verification expectations

A dependency rule is considered verified only after checking Go imports, route wiring, repository/table access and event producers/consumers. The presence of a proposed boundary in documentation is not proof that the current code enforces it. Before changing a boundary, record the concrete package, call path, table or contract involved and preserve existing workflow behavior.
