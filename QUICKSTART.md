# NIDAW Quickstart

1. Install Docker Engine/Desktop with Docker Compose v2.
2. Copy `env.example` to `.env`. For the checked-in development Compose configuration, set `DB_PASSWORD=nidaw_dev` and set `MINIO_USER`/`MINIO_PASSWORD` to local-only values.
3. Start local infrastructure: `docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml up -d`.
4. Export database settings and apply migrations:

   ```bash
   set -a; source .env; set +a
   DB_PASSWORD=nidaw_dev ./scripts/migrations/migrate-up.sh
   ```

5. Seed optional development data: `DB_PASSWORD=nidaw_dev ./scripts/seed/seed-data.sh`.
6. Start/restart the API: `cd services/api && go run ./cmd/server`.
7. Start a Flutter app with `cd apps/consumer_app && flutter pub get && flutter run` or `cd apps/driver_app && flutter pub get && flutter run`.
8. Start the admin console with `cd apps/admin_console && npm install && npm run dev`.

The repository's `scripts/setup.sh` currently attempts database seeding without applying migrations first. Do not rely on `make setup` for a fresh database until that bootstrap ordering is corrected. The Compose stack is for local development, not production. Production deployment is deliberately blocked by `scripts/deploy.sh`; see [deployment runbook](docs/operations/deployment-runbook.md).
