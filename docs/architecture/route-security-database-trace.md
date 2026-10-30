# NIDAW Route, Security, and Database Trace — Phase 0 Supplement

## Scope and evidence standard

This is a static source review of the supplied repository snapshot. It identifies registration and implementation evidence; it does not prove that external services, production credentials, or production data are available. Runtime behavior still requires tests in a dependency-enabled environment.

## Runtime composition and route reachability

Primary composition root: `services/api/cmd/server/main.go`.

| Capability | Registration evidence | Status from source inspection | Follow-up |
|---|---|---|---|
| Authentication | `authhttp.NewRouter(...)` mounted at `/` | Mounted; login/register/refresh are public, `me/logout/profile/change-password` are behind auth middleware in the auth router | Verify rate limiting and authorization behavior with route tests |
| Nidus | `nidushttp.NewRouter(nidusDeps)` mounted at `/` | Mounted; dependencies include DB, event bus, auth, location cache, matching, ETA, pricing, WebSocket hub | Build route-level auth matrix; test optional routes behind feature flags |
| Notifications | Routes registered under `/api/v1/notifications` only when `EnableNotifications` is true | Feature-flagged; module initializes schema and event consumers | Verify auth on every registered route and event-consumer idempotency |
| Chat | Routes registered under `/api/v1/chat` only when `EnableChat` is true | Feature-flagged; schema initialization is performed at startup | Confirm authorization binds each ride/chat to participant identity |
| Telephony | Routes registered under `/api/v1/telephony` only when `EnableMaskedCalling` is true | Feature-flagged; requires provider configuration | Verify provider webhook/auth assumptions and secret handling |
| Selfie verification | Routes registered under `/api/v1` only when `EnablePreSelfie` is true | Feature-flagged; startup rejects enabled configuration without signing key | Verify file access controls, expiry, and signed URL replay semantics |
| Ledger | `/api/v1/ledger` mounted only when internal ledger is enabled | Conditional; route constructor applies JWT middleware and handlers include admin checks | Test role/resource authorization and startup configuration variants |
| Payment-provider callbacks | `/api/v1/payments` registered inside ledger-enabled and provider-resolver-configured branch | Conditional on both ledger and provider configuration | Verify provider signature checks and replay protection per rail |
| Corpus | `services/api/internal/modules/corpus` exists but is not imported/mounted by `cmd/server/main.go` | No runtime route reachability established from composition root | Define intended API and compose only after contracts and authorization are reviewed |
| Logix | `services/api/internal/modules/logix` exists but is not imported/mounted by `cmd/server/main.go` | No runtime route reachability established from composition root | Define intended API and compose only after domain behavior is validated |
| Legacy payment processing | `services/api/internal/modules/payment/interfaces/http/handlers/payment_handler.go` exists; no corresponding handler/router is mounted in `main.go` | HTTP processing path is not reachable from the inspected composition root | Decide whether to integrate, deprecate, or remove after consumers and data ownership are mapped |
| Payment-method registry | `payments` application service is constructed and passed into Nidus dependencies | Exposed through Nidus router conditionally; this is not the same as mounting legacy transaction processing | Document ownership and API semantics to avoid confusing payment methods with charge lifecycle |

The root `docker-compose.yml` is a documented placeholder that directs users to `platform/docker/compose/base.yaml` plus environment overlays. `platform/kubernetes/` manifests and gateway configuration also exist. The active deployment path must be selected and validated before relocating these files.

## Security and authorization observations

### Verified controls in source

- Authentication router separates public login/register/refresh from protected account routes using `authService.Middleware()`.
- The ledger router wraps registered routes with JWT middleware, and the handler includes an additional admin guard for privileged mutations.
- The Nidus WebSocket hub is configured with a Postgres-backed ride participant subscription authorizer in the composition root.
- Optional selfie verification refuses to start when enabled without a sufficiently configured signing key.
- Several optional capabilities are disabled by feature flags by default in configuration, reducing accidental activation but requiring environment-specific verification.

### Risks requiring targeted verification

- Tenant/org context appears in token and logging infrastructure, but static search did not establish systematic tenant checks throughout product repositories and handlers. This is a verification gap, not proof that every operation is vulnerable. Corpus must enforce organization isolation at application and persistence boundaries before it is considered ready.
- Route-level middleware is inconsistent by design: some routers own their middleware, while routes mounted directly in `main.go` may rely on handler-level checks. Build an endpoint matrix covering authentication, role/permission checks, resource ownership, and tenant checks for every route.
- Public payment callbacks require per-provider signature verification, replay/deduplication, and reconciliation tests. Do not treat callback payload claims alone as authoritative payment evidence.
- Review sensitive log fields and request-body logging, especially identity, location, payment, and corporate travel data. Avoid recording secrets or unnecessary personal information.
- Existing `docs/security/SECURITY_AUDIT_REPORT.md` is a prior narrative report, not a substitute for route-by-route verification; its assertions must be revalidated against current code and tests.

## Migration order and compatibility findings

Migrations are under `data/migrations/postgres/001..017` with Timescale-specific SQL in `data/migrations/timescale/`.

- `015_payment_integrity.sql` and `016_payment_integrity_base.sql` both define `transactions` and overlapping columns/indexes with `IF NOT EXISTS` guards. Their comments describe the intended compatibility, but no migration runner or clean-install/upgrade execution was verified in this pass.
- Migration 016 additionally creates `reconciliation_reports` and `payouts`; those objects are not created by 015. Thus the pair is not semantically interchangeable as a complete migration set even though the `transactions` base shape overlaps.
- Before changing order or consolidating these files, test the actual runner on an empty database and a representative database that has already applied earlier migrations. Confirm migration bookkeeping, transaction behavior, constraints, and rollback/forward-recovery expectations.
- `data/migrations/postgres/003_seed_data.sql` is located in the same ordered migration directory as schema migrations. Confirm whether production migration automation executes it; seed/test data must not be accidentally applied to production.
- Database initialization and some feature-module `EnsureSchema` calls occur at application startup. Inventory every startup schema mutation and decide which are safe additive compatibility checks versus production migrations that should be separately controlled.

## SQL ownership status

The repository includes the main PostgreSQL schema, numbered migrations, Timescale hypertable setup, and dbt staging/mart queries. Ownership assignments in `database-ownership-inventory.md` remain provisional until each product query/repository write path is mapped. Shared PostgreSQL does not imply shared write authority. Cross-domain SQL joins and writes need to be classified individually.

## Commands attempted

- `GOPROXY=off go test ./...` from `services/api/`: blocked before tests execute because dependencies such as chi, uuid, zap, pgx, Redis, JWT, and Kafka are not available in the local module cache and offline lookup is disabled.
- Flutter build/test: not run because the Flutter SDK is unavailable in this environment.
- Admin console build: previous baseline record says TypeScript/Vite build passed; rerun after any frontend changes.

## Phase 0 closure criteria

Phase 0 should not be declared complete until route authorization, SQL ownership, migration runner behavior, and deployment path have either been verified by executable tests or recorded as specific external-environment blockers with reproducible local alternatives. Do not perform broad structural moves before those criteria are met.

## Deployment and migration-runner verification supplement

### Toolchain availability in this audit environment

| Tool | Result | Consequence |
|---|---|---|
| Go | Available | Go commands can be attempted, but module dependencies were not available from the earlier baseline run. |
| Node.js/npm | Available | Admin console production build was rerun and passed: `npm --prefix apps/admin_console run build` (TypeScript project build + Vite production bundle). |
| Flutter | Not installed | Consumer and driver Flutter builds/tests cannot be run here. |
| Docker / Docker Compose | Not installed | Compose configuration cannot be validated with `docker compose config` and services cannot be started. |
| psql | Not installed | Migration scripts cannot be executed against PostgreSQL in this environment. |
| Helm / kubectl | Not installed | Kubernetes/Helm manifests and deployment behavior cannot be validated against a cluster here. |

### Deployment-source conflicts

The repository currently has several competing operational entry points:

- The Makefile `dev` target now uses the explicit `platform/docker/compose/base.yaml` and `platform/docker/compose/dev.yaml` pair; root `docker-compose.yml` remains guidance-only.
- `scripts/setup.sh` now invokes the documented Compose file pair and the relocated seed script; its end-to-end behavior still requires a Docker-enabled run.
- `Makefile` runs driver tests from `apps/driver_app/`, but the canonical directory is `apps/driver_app/`.
- `scripts/deploy.sh` attempts to build `./apps/driver_app`, while the actual driver directory is `apps/driver_app/`; it references `platform/kubernetes/nidaw`, `platform/kubernetes/ml`, and `platform/kubernetes/analytics` chart paths that must be checked against actual chart contents before this script can be considered a supported deployment path.
- CI has distinct backend, frontend, staging, production, and security workflows, with differing assumptions about what is deployed. The repository does not yet identify one canonical deployment workflow.

These are source-level path/configuration mismatches. Because Docker, Helm, and kubectl are unavailable here, their runtime impact has not been exercised. Phase 1 must not move files until the active path is selected and every workflow is updated together.

### Migration runner defects and risks

Static inspection of `scripts/migrations/migrate-up.sh` found the following concrete risks:

1. **Applied-count reporting is incorrect.** The `while read` loop runs as the last stage of a pipeline (`get_pending_migrations | while ...`). In Bash, that loop normally executes in a subshell, so changes to `pending_count` do not propagate to `main`; successful migrations can still be reported as “No pending migrations.”
2. **Migration application and bookkeeping are not atomic together.** The SQL file is run in its own transaction, then a separate `psql` invocation inserts the `schema_migrations` row. If the process fails between those operations, the migration can be applied without being recorded and may be rerun on the next attempt.
3. **Pending selection relies on the highest applied version, not missing individual migrations.** `get_pending_migrations` applies only filenames whose version compares greater than the current maximum. If an out-of-order migration is recorded, lower-numbered unapplied migrations can be skipped. The current three-digit versions also make lexical order work only while the naming convention remains consistent.
4. **The target-version loop control is not reflected in the parent shell.** The loop's `break` stops the pipeline subshell's loop, not the parent shell, and reporting state is also lost across that pipeline.
5. **Seed data is mixed into the ordered migration directory.** `003_seed_data.sql` will be considered a normal migration by this runner. Verify its contents and production policy before using this runner in a deployed environment.
6. **Checksums are recorded but not validated on subsequent runs.** The script stores SHA-256 but does not compare recorded checksums with current files, so edits to already-applied migration files are not detected by the runner.
7. **Migration file execution is sorted lexically by path.** That is deterministic for the current zero-padded PostgreSQL filenames, but it is not a substitute for explicit per-migration applied-state tracking.

Both migration scripts pass `bash -n` syntax validation. This does not validate SQL semantics or migration execution. No migration changes have been made in Phase 0; correcting the runner belongs in the implementation phase after its expected compatibility behavior is covered by tests.

### Phase 0 disposition

- Admin console build: **verified pass** in this environment.
- Go test suite: **blocked/inconclusive**, not a pass.
- Flutter tests: **blocked** because Flutter is unavailable.
- Compose, PostgreSQL migrations, Helm, and Kubernetes: **not executable here** because their tools/services are unavailable.
- Static deployment and migration-runner defects: **documented with source paths above**.
- Phase 0 acceptance: **not yet passed**. The missing runtime checks need either a dependency-enabled environment or explicitly accepted, reproducible alternative evidence before repository relocation.
- Admin lint: `npm run lint --prefix apps/admin_console` failed before linting because `eslint` was not found in the installed package environment. This is not a lint pass; confirm whether ESLint is intentionally omitted from `package.json`/lockfile or whether the archive's dependency installation is incomplete.

### Additional payment migration ordering contradiction

The migration comments disagree about the required order: `015_payment_integrity.sql` says `016_payment_integrity_base.sql` is a prerequisite, while the current lexically sorted runner applies `015` before `016`. Migration 015 also creates `transactions` itself “so either ordering converges,” whereas migration 016 describes itself as creating the missing base objects and adds the `reconciliation_reports` and `payouts` tables. This appears intentionally idempotent at the SQL-object level, but the documented prerequisite/order contract is contradictory and should be normalized only after clean-install and upgrade tests establish the supported sequence.

Both 015 and 016 contain explicit `BEGIN;` and `COMMIT;` statements, while `migrate-up.sh` invokes `psql --single-transaction`. That combination can cause the migration file's explicit `COMMIT` to end the transaction started by psql before the runner's wrapper reaches its own end. As a result, the runner's claim that each migration is applied in one transaction is not reliably represented by the combined script. Remove one transaction-control layer after confirming all migration statements are compatible with the chosen runner, and test failure rollback with a deliberate failing statement in a disposable database.
