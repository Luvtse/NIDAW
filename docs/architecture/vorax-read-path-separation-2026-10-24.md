# Vorax read-path application/persistence separation — 2026-10-24

## Scope

Moved Vorax restaurant discovery, restaurant detail, menu listing, authenticated order listing, and order tracking out of the HTTP adapter's direct SQL path.

## Changes

- Added `application.ReadService` with explicit restaurant and order reader contracts and bounded pagination (default 20, maximum 100).
- Added application DTOs for restaurants, menu items, order summaries, and tracking responses.
- Added a PostgreSQL `Readers` adapter that owns query execution, row scanning, query errors, and not-found translation.
- Updated HTTP handlers to parse request parameters, invoke application use cases, map errors to HTTP status codes, and serialize responses.
- Kept order creation in its previously extracted application service/PostgreSQL transaction adapter.
- Added application tests for pagination defaults and maximum bounds.

## Validation

- `gofmt` completed on all changed Go files.
- Static assertion confirms no direct SQL, database field, or pgx dependency remains in `modules/vorax/interfaces/http/router.go`.
- Domain-only tests are attempted separately where the environment permits.
- Application, adapter, and HTTP package tests could not run in the current offline environment because dependencies including `github.com/google/uuid`, `github.com/jackc/pgx/v5`, and `github.com/go-chi/chi/v5` are not cached. No compile or integration-test pass is claimed.

## Remaining

- Verify these packages with dependencies available.
- Add PostgreSQL integration coverage for not-found behavior, user ownership, and query results.
- Continue cross-product boundary review and payment/fulfillment orchestration work. This checkpoint does not mean the overall modular-monolith restructuring is complete.
