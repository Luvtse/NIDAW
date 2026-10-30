# Haven booking lifecycle persistence separation — 2026-10-24

## Change

Moved booking cancellation and room-inventory provisioning persistence out of Haven HTTP handlers and into the PostgreSQL adapter, exposed through the Haven booking application service.

- `BookingService.Cancel` delegates cancellation to a lifecycle persistence boundary.
- `BookingWriter.CancelBooking` owns the transaction that locks a user-owned booking, validates its cancellable state, releases the stay's reserved inventory, updates booking status, and commits atomically.
- `BookingService.ConfigureInventory` validates the capacity range before persistence.
- `BookingWriter.SetInventory` owns the conditional upsert and returns a typed conflict when the requested capacity is below existing reservations.
- HTTP handlers retain request parsing, authentication/authorization, and HTTP status mapping; they no longer issue cancellation or inventory mutation SQL.
- Added application-level tests for cancellation delegation and rejection of invalid inventory capacity before persistence.

## Validation

- `gofmt` completed on changed Haven files.
- Haven and Vorax domain unit tests pass with `GOPROXY=off`.
- Haven application, PostgreSQL adapter, and HTTP package tests were attempted but could not run because required Go modules are not cached and dependency downloads are unavailable in this environment. Compilation of those packages is therefore unverified.
- Static source inspection confirms cancellation and inventory mutation SQL are no longer in the Haven HTTP handlers.

## Remaining Haven extraction work

Hotel discovery/detail queries and booking list/detail queries remain in HTTP handlers. The HTTP layer still depends on the shared database adapter for those reads. These are explicitly not considered complete by this checkpoint.
