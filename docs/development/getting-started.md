# Getting Started

## Prerequisites

- Git.
- Docker Engine or Docker Desktop with Docker Compose v2.
- Go toolchain compatible with `services/api/go.mod` (module declares Go 1.19).
- Flutter/Dart compatible with each app's `pubspec.yaml`.
- Node.js/npm compatible with `apps/admin_console/package.json`.

Platform-specific Android/iOS builds additionally require Android Studio/Android SDK and Xcode on macOS.

## Prepare local environment

```bash
cp env.example .env
```

For the checked-in development Compose override, set `DB_PASSWORD=nidaw_dev` so the host-side migration and seed scripts can connect to the local PostgreSQL container. Set `MINIO_USER` and `MINIO_PASSWORD` to local-only values; the base Compose file requires them. Review all other provider credentials and use development/sandbox values only. Never commit `.env`.

Start the local stack:

```bash
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml up -d
```

The current `scripts/setup.sh` starts the same Compose files and then calls the seed script, but it does not apply database migrations first. Therefore it is not a reliable fresh-database bootstrap and `make setup` may fail while seeding a new database. Use the explicit order below instead.

## Apply database migrations and optional seed data

The migration and seed shell scripts read environment variables from the process; they do not automatically source the repository `.env` file. In a new terminal from the repository root:

```bash
set -a; source .env; set +a
DB_PASSWORD=nidaw_dev ./scripts/migrations/migrate-up.sh
DB_PASSWORD=nidaw_dev ./scripts/seed/seed-data.sh
```

The seed step is optional and must only be used with disposable development data. Do not run seed scripts against production.

## Run the API

The backend configuration loader reads `.env` from its current working directory. When `.env` is at the repository root, export it before changing into `services/api`:

```bash
set -a; source .env; set +a
cd services/api
go mod download
go run ./cmd/server
```

The API reads configuration through `internal/shared/config`. It requires a reachable PostgreSQL database and Kafka broker at startup. Product-specific production settings may impose additional startup requirements.

## Run consumer app

```bash
cd apps/consumer_app
flutter pub get
flutter run
```

## Run driver app

```bash
cd apps/driver_app
flutter pub get
flutter run
```

## Run admin console

```bash
cd apps/admin_console
npm install
npm run dev
```

The admin console package also defines `npm run build` and `npm run lint`. Confirm the configured API proxy and authentication token flow for the environment before using administrative actions.

## Stop local infrastructure

From the repository root:

```bash
make clean
```

This stops the Compose stack but retains named volumes. Do not use volume deletion unless you intend to destroy local database, cache, broker and object-storage data.
