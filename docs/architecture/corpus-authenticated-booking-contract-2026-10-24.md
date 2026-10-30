# Corpus authenticated booking contract review — 2026-10-24

## Implemented in this checkpoint

- Added the protected `POST /api/v1/corpus/bookings` route and registered it in the API composition root.
- The handler derives `UserID` from the validated authentication context. The request cannot supply an employee ID.
- The request must supply a corporate account UUID, service type, booking data, and optional payment method. Membership is resolved by `(authenticated user_id, corporate_id)` and requires both the employee membership and corporate account to be active.
- The booking record and `corpus.booking.created` event use the resolved corporate employee membership ID, not the user ID supplied by the token.
- Request body size is capped at 256 KiB, unknown top-level fields are rejected, and multiple JSON values are rejected.
- Added static regression assertions for auth middleware, identity resolution, active-account membership, server wiring, and persisted identity.

## Security and runtime caveats

- The corporate account UUID is a selector, not proof of access; the adapter enforces membership in that account for the authenticated user.
- This checkpoint does not establish that all service-specific `booking_data` fields have a stable, versioned API contract. The existing domain evaluator still validates the current generic map shape.
- The HTTP layer is wired but has not been compiler-verified because required Go modules are unavailable in the current offline environment.
- PostgreSQL migration compatibility, runtime authorization, error mapping, and outbox delivery need integration tests before production use.

## Additional testability and error handling

The HTTP handler now depends on a narrow booking-creator interface, enabling transport tests without a database. Tests cover missing authentication context, rejection of a client-supplied `employee_id`, and passing the authenticated user ID to the application. Internal application/database error strings are not echoed verbatim in HTTP responses.
