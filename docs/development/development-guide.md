# Development Guide

## Repository conventions

- Backend: `services/api`, Go module `nidaw-backend`; keep domain/application/infrastructure/interfaces separated within modules.
- Consumer and driver: independent Flutter projects with separate dependency manifests and test suites.
- Admin: React/TypeScript/Vite project under `apps/admin_console`.
- SQL migrations: `data/migrations`; migration scripts: `scripts/migrations`.
- Shared platform code: `services/api/internal/shared`; do not place product business rules there.

## Backend commands

```bash
cd services/api
go fmt ./...
go vet ./...
go test ./...
go test -race ./...
```

The root `make test` target runs backend race/coverage tests and both Flutter test suites sequentially. Run it from the repository root. These commands are verification instructions, not a statement that the current repository has passed them in every environment.

## Flutter commands

Run in each app directory:

```bash
flutter pub get
flutter analyze
flutter test
```

Use the app's declared build-time configuration for API, WebSocket, maps and other client-safe values. Never embed server credentials, JWT signing secrets or payment-provider secrets in a mobile binary.

## Admin console commands

```bash
cd apps/admin_console
npm install
npm run lint
npm run build
```

## Database changes

1. Identify the owning domain and migration sequence.
2. Make schema changes additive and backward-compatible where possible.
3. Update repository code and contract documentation together.
4. Test migrations on a disposable database and verify both upgrade and rollback behavior.
5. Back up and verify restore before production schema operations.
6. Do not modify production data manually as a substitute for a reviewed migration.

## API and event changes

Update handlers, DTOs, clients, gateway route definitions, event schemas and the API reference as applicable. Check authentication/authorization and resource ownership. For events, define idempotency and retry semantics and use a transactional outbox where atomicity is required.

## Code review checklist

- Domain ownership is respected and no dependency cycle is introduced.
- Authorization is enforced server-side.
- Errors are actionable without leaking secrets.
- Financial operations are auditable and idempotent.
- Logs contain correlation identifiers but not credentials or sensitive personal data.
- Migrations are safe for mixed application versions.
- Relevant tests and documentation are updated.
- No generated build output, local secrets or temporary audit documents are committed.
