# NIDAW Domain Boundaries and Migration Sequence

## Intended ownership (target, to validate against source)

| Domain | Owns | Must not own |
|---|---|---|
| Nidus | Ride requests, dispatch, matching decisions, trip lifecycle, rider/driver operational workflows | Payment-provider lifecycle or corporate travel approval records |
| Haven | Accommodation inventory, availability, rates specific to accommodation, reservations and reservation lifecycle | Payment execution or Corpus policy decisions |
| Vorax | Merchants, menus, food orders and order lifecycle; delivery coordination state | Nidus private implementation or financial settlement authority |
| Logix | Shipments, freight quotes, carrier coordination, shipment documents and shipment lifecycle | Payment execution or Corpus approval records |
| Corpus | Corporate travel requests, tenant policy, approvals, budgets and orchestration state | Private product tables/state or product internal packages |
| Payments | Payment authorization/capture/refund execution and provider integration | Product-specific ride/reservation/order/shipment lifecycle |
| Ledger/Finance | Accounting entries, financial posting and reconciliation | Product operational state transitions |
| Notifications | Message delivery and channel adapters | Product business decisions |
| Promotions | Promotion eligibility and redemption rules | Product lifecycle ownership |
| Identity/Access | Authentication and shared authorization primitives | Product-specific business policy |
| Platform | Configuration, gateway, observability, persistence adapters and shared technical utilities | Catch-all business logic |

This is the intended boundary model from the implementation specification, not a claim that the current code already conforms. Current evidence includes a `payment`/`payments` naming ambiguity and a large composition root. No direct-import violation should be declared without a full import graph and ownership trace.

## Required dependency direction

- Product application code may use its own domain model and approved shared technical abstractions.
- Product-to-product workflows use explicit application ports/adapters or versioned contracts/events.
- Corpus orchestrates products through published interfaces; it does not mutate their private tables or import their internal implementation packages.
- Payments and Ledger expose narrow capabilities; product domains retain their own business lifecycle.
- Infrastructure implements interfaces owned by application/domain layers and does not introduce reverse business dependencies.
- No cycles between product domains; architecture checks should enforce the approved graph.

## Dependency-ordered migration sequence

1. **Finish Phase 0 audit:** map imports, routes, table ownership, migrations, client contracts, CI/deploy paths, auth and tenant boundaries. Record existing test failures.
2. **Fix baseline workflow defects:** correct verified commands and document native toolchains without changing application behavior.
3. **Canonical layout mapping:** create a file/path mapping; identify every workflow, Docker context, script, app reference and deployment path. Move one coherent application at a time, updating references atomically.
4. **Build reproducibility:** root orchestration should call native Go, Flutter and Node toolchains without merging package managers. Validate clean-checkout behavior.
5. **Domain boundaries:** resolve duplicate/ambiguous module ownership, define application ports and adapters, add architecture checks, and eliminate only proven violations.
6. **Data ownership and workflow invariants:** map every business table, transaction, idempotency key, state transition, constraint and recovery path; add tests before changing behavior.
7. **API/event contracts:** inventory consumers, version stable contracts, add compatibility validation, and only then refactor cross-product calls.
8. **Reliable async behavior:** introduce/complete transactional outbox only where business change + event publication must be atomic; make consumers idempotent and observable.
9. **Composition root and security:** make dependencies explicit, improve startup/shutdown, authorization, tenant isolation and secret handling.
10. **Client alignment and operations:** validate consumer/driver/admin contracts, observability, deployment and recovery workflows.
11. **Extraction assessment:** extract only a proven candidate with an operational reason, contract stability, data ownership and independent test/deploy readiness.

## Phase 0 checklist

- [x] Inspect archive integrity and top-level structure.
- [x] Inventory Go modules and primary application toolchains.
- [x] Establish an initial five-product evidence matrix.
- [x] Run admin production build.
- [x] Attempt Go test baseline and record timeout honestly.
- [x] Check Flutter availability and record blocker.
- [ ] Complete Go import graph and runtime dependency mapping.
- [ ] Trace all gateway routes to handlers/upstreams and clients.
- [ ] Map SQL migrations, tables, repositories and authoritative owners.
- [ ] Audit API contracts, webhooks, event payloads and consumers.
- [ ] Audit authorization, tenant isolation, secrets and sensitive logging.
- [ ] Establish repeatable Go and Flutter test baselines.
- [ ] Confirm active deployment path and clean-checkout setup.
- [ ] Obtain Phase 0 acceptance before file moves.
