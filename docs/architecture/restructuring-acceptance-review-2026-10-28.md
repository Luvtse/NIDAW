# NIDAW restructuring acceptance review — 2026-10-28

## Decision

**Structural review: conditionally ready for a feature-development handoff. End-to-end/runtime acceptance: NOT READY / NOT VERIFIED.**

This review intentionally does not implement missing Haven, Vorax, Logix, or Corpus business features. Nidus remains the principal existing product whose behavior must be protected by regression tests. The other product modules are under development; the presence of module directories, adapters, and partial application services is not evidence that their user-facing workflows are complete.

A feature-development session may proceed if it treats the blockers below as explicit constraints and does not claim the full application is tested or runtime-ready. A formal restructuring exit requiring a successful build and runnable regression suite remains blocked until a dependency-enabled environment is available.

## Scope of this pass

- Re-run static architecture and deployment-source checks.
- Check Go formatting and source-script syntax.
- Exercise available migration-runner mock tests.
- Check migration numbering and selected configuration artifacts.
- Record runtime blockers and product-specific gaps without fabricating database contracts or unfinished features.

## Validation evidence

| Check | Result | Evidence / limitation |
|---|---|---|
| Product-module import boundary | PASS | `scripts/architecture/check-go-product-boundaries.py`; direct Go product-to-product imports were not found. This does not prove runtime isolation or data ownership. |
| Architecture checks | PASS | All 16 scripts under `scripts/architecture/` passed. |
| Deployment/source static checks | PASS with known gaps | Audit scripts validate the intended Helm path and several contracts; Kustomize overlay checks still report missing referenced resources. |
| Go formatting | PASS | All Go files under `services/api` were formatted with `gofmt`; no remaining files are reported by `gofmt -l`. |
| Python source syntax | PASS | All 28 Python files under `scripts/` parsed successfully after adding the dashboard check. |
| Shell syntax | PASS | Migration runner and test scripts, plus root/backup/seed/audit/test shell scripts, passed `bash -n`. |
| Migration runner regression tests | PASS (mocked) | Five scripts under `scripts/migrations/tests/` passed. The “real wrappers” test explicitly uses mocked `psql`; no SQL was executed by PostgreSQL. |
| Additional shell regression tests | PASS | Kong exposure matrix shell test and driver WebSocket configuration test passed. |
| Migration numbering | PASS | 24 up migrations have unique, contiguous versions 001–024 after excluding explicitly named `_down.sql` files. This does not prove the SQL executes or is compatible with deployed databases. |
| Grafana dashboard JSON | PASS after repair | `platform/monitoring/grafana/dashboards/nidaw-overview.json` had a duplicated/truncated prefix and was repaired. `scripts/audit/test-grafana-dashboard-json.py` now checks strict JSON, a non-empty panel list, integer panel IDs, and uniqueness; seven panels are present. |
| Go package tests/build | BLOCKED | `GOPROXY=off go test ./internal/modules/logix/application/services ./internal/modules/logix/infrastructure/postgres` cannot resolve uncached dependencies (`google/uuid`, `pgx/v5`, `zap`, `kafka-go`, and transitive dependencies) before compilation. No Go test pass is claimed. |
| PostgreSQL / Kafka integration | NOT RUN | `psql`, `pg_isready`, and `kafka-topics` are unavailable; Docker/Podman are unavailable. |
| Helm/Kubernetes rendering/runtime | NOT RUN | `helm` and `kubectl` are unavailable. Static checks do not replace chart rendering, cluster RBAC checks, or smoke tests. |
| Flutter client tests | NOT RUN | `flutter` is unavailable. |

## Findings that must remain visible

### Product boundaries and runtime composition

- Static import boundaries are guarded, and application/persistence separation has been improved in Haven, Vorax, Logix, and Corpus.
- Haven, Vorax, and Corpus have router registration visible in `services/api/cmd/server/main.go`; feature flags and dependencies can still affect runtime reachability.
- The reviewed composition root does not mount a Logix HTTP router. Logix outbox startup wiring is present, but the load-matcher workflow has no verified active call site. Do not claim the Logix workflows are runtime-enabled.
- Existing Nidus functionality has not had its Go regression suite executed in this environment. Treat Nidus behavior as unverified by this pass, not as failed and not as newly certified.

### Database contracts and migrations

- Static schema inventory identifies no checked-in PostgreSQL `CREATE TABLE`/`ALTER TABLE` evidence for `carriers`, `customs_declarations`, or `shipments`, although Logix adapters reference them. This does not prove the objects are absent from deployed databases; an authoritative owner/provisioning source is still required.
- Do not invent those table definitions or wire Logix load matching into runtime until the schema owner, column types/nullability, constraints, indexes, and status/transaction semantics are confirmed.
- Migration scripts have mocked regression coverage, but there is no live clean-database run, representative upgrade run, or deployed migration-ledger comparison in this environment. Rollback remains unavailable for most historical migrations without matching down scripts; use reviewed forward migrations or a verified restore plan rather than assuming rollback exists.

### Events and cross-product contracts

- Static checks cover selected consumer commit behavior, topic routing, outbox contracts, and idempotency guards.
- The event catalogue is explicitly partial. Kafka topic existence/ACLs, consumer payload compatibility, downstream deduplication, and broker-backed replay/failure behavior remain unverified.
- Outbox delivery is at-least-once; downstream consumers must deduplicate stable event identities. Do not infer exactly-once delivery.

### Routing and deployment

- The route registry is source-derived, not a runtime Chi-router export. The existing route review notes a WebSocket middleware/comment contradiction and outstanding authorization/isolation tests.
- Helm is the observed staging/production deployment path and passed static contract checks, but actual Helm rendering and cluster deployment were not run.
- Kustomize overlays remain non-renderable in the current tree: the `nidaw-frontend` Deployment is absent from the base and the overlays reference missing Nginx configuration files; staging also references a missing `.env.staging`. These are known deployment defects, even though Kustomize is not the workflow's active staging/production deployment path.
- `database/Redis Schema for Real-Time State.json` contains Redis CLI examples rather than JSON, and `database/Kafka Event Schemas .json` contains commented event examples rather than one strict JSON document. VS Code configuration files use JSON-with-comments. These were not silently treated as strict JSON data files.

## Acceptance gates for full restructuring exit

- [ ] Install/resolve dependencies in a supported environment and compile/test the Go API packages.
- [ ] Run Nidus regression tests and retain the result as the compatibility baseline.
- [ ] Run relevant PostgreSQL migrations from an empty disposable database and a representative upgrade state; record migration ledger/checksum behavior.
- [ ] Verify API startup and readiness with real PostgreSQL and Kafka, then exercise the existing Nidus smoke paths.
- [ ] Resolve or explicitly defer the WebSocket authentication contract and test the chosen handshake/room authorization behavior.
- [ ] Establish authoritative schema ownership for Logix's `carriers`, `customs_declarations`, and `shipments` before enabling those paths.
- [ ] Complete the event catalogue and validate selected producer/consumer contracts against a broker-backed test environment.
- [ ] Render the active Helm chart and run environment-backed deployment/smoke checks when the relevant tools and credentials are available.

## Handoff guidance

The next session should implement missing business features against the current module boundaries, but should not treat this report as proof that the repository builds or that all products are runnable. Keep Nidus regression compatibility as a hard requirement. For unfinished products, implement features only after their authoritative persistence and external-service contracts are established; use explicit deferred/blocked status rather than guessed schemas or placeholder behavior.
