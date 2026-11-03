# Contributing to NIDAW

## Before changing code

1. Read [system architecture](docs/architecture/system-architecture.md), [domain boundaries](docs/architecture/domain-boundaries.md) and the relevant [product document](docs/products/README.md).
2. Identify the owning module, API/client consumers, database migrations and event contracts.
3. Preserve existing behavior unless the change explicitly requires a documented behavior change.
4. Do not create phase reports, pass-number documents or duplicate documentation. Update the authoritative subject document instead.

## Development setup

Follow [getting started](docs/development/getting-started.md). Do not commit `.env`, credentials, generated build output or local database files.

## Engineering requirements

- Keep domain, application, infrastructure and interface responsibilities separate.
- Respect product boundaries and shared capability ownership.
- Validate input and enforce authorization on the server.
- Make financial operations auditable and idempotent.
- Use safe, backward-compatible database migrations.
- Use an outbox and idempotent consumers for workflows requiring reliable event publication.
- Add or update tests for changed behavior; run the relevant test suites.
- Update API, event, configuration and operational documentation when contracts change.

## Local verification

Run Go formatting on changed Go files, then run the relevant checks:

```bash
cd services/api && go test ./...
cd apps/consumer_app && flutter analyze && flutter test
cd apps/driver_app && flutter analyze && flutter test
cd apps/admin_console && npm run lint && npm run build
```

Run formatting only on intended Go source files; `gofmt -w ./...` is shown as a general reminder but should be applied with care in a working tree. The root `make test` target is also available.

## Pull request checklist

- [ ] Scope and domain ownership are clear.
- [ ] Authorization and tenant/resource ownership are enforced.
- [ ] Tests cover changed behavior and failure cases.
- [ ] Migrations are safe and reversible where applicable.
- [ ] API/event/client contracts are compatible or explicitly versioned.
- [ ] Logs and errors do not expose secrets or sensitive data.
- [ ] Relevant authoritative documentation is updated.
- [ ] No secrets, temporary reports or generated artifacts are included.
