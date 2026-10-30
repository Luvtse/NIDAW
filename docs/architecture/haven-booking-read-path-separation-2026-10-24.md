# Haven booking read-path separation — 2026-10-24

## Scope

This checkpoint moves the authenticated booking list and booking detail SQL out of Haven's HTTP handlers and into the PostgreSQL adapter. The application service exposes user-scoped `List` and `Get` use cases. The list limit is clamped to the existing API range (default 20, maximum 100), and the detail query applies both booking ID and user ID to the database predicate.

## Boundary after this checkpoint

- HTTP: authentication/context extraction, request parsing, status mapping, and JSON responses.
- Application: booking list/detail use cases and pagination bounds.
- PostgreSQL adapter: SQL, row scanning, and database error translation.
- Domain: stay and booking policy rules.

Hotel discovery/detail SQL remains in the HTTP adapter and is explicitly not considered complete. PostgreSQL-backed runtime behavior and package compilation remain pending until dependencies are available.
