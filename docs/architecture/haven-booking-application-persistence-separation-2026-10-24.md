# Haven booking application/persistence separation — 2026-10-24

## Scope

This checkpoint moves the Haven booking-creation use case's orchestration and atomic PostgreSQL transaction out of the HTTP handler. It does not claim that all Haven persistence has been extracted, nor that Vorax has completed the same refactor.

## Changes

- `internal/modules/haven/application/booking_service.go` defines the booking command/result, validates stay and occupancy policy, and depends on a narrow `BookingWriter` interface.
- `internal/modules/haven/infrastructure/postgres/booking_writer.go` owns the transaction: hotel price/status snapshot, row-locked date inventory read, capacity check, inventory reservation, booking insertion, and commit.
- `internal/modules/haven/interfaces/http/router.go` now parses HTTP input, calls the application service, maps application/domain errors to HTTP responses, and serializes the result.
- `booking_service_test.go` checks that invalid stays do not reach persistence and valid commands are delegated.

## Invariants preserved

- Inventory must be explicitly configured for every night; no capacity is inferred.
- Inventory rows are locked in date order before capacity is checked.
- Capacity reservation and pending booking creation share one transaction.
- Prices are read from the database and the total is calculated server-side.
- Public response status and shape for successful booking creation remain unchanged.

## Remaining work

- Move Haven cancellation and inventory-administration SQL out of the handler.
- Extract the remaining Haven catalog queries into a repository.
- Apply the same application/repository separation to Vorax order creation and read paths.
- Add PostgreSQL integration tests for concurrent booking requests and rollback behavior.
- Run full module tests when dependencies are available; this environment's dependency downloads timed out during this checkpoint.
