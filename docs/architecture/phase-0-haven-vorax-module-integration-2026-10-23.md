# Haven and Vorax Modular-Monolith Integration

Date: 2026-10-23

## Scope

This change adds in-process HTTP modules for Haven and Vorax to the existing Go API composition root. It does not create separate deployable services and does not change the Kong upstream target: both product APIs are served by `nidaw-backend:8080`.

## Haven endpoints

- `GET /api/v1/haven/hotels?city=&country_code=&limit=` — active hotel discovery.
- `GET /api/v1/haven/hotels/{hotelID}` — active hotel detail.
- `PUT /api/v1/haven/hotels/{hotelID}/inventory/{YYYY-MM-DD}` — administrator-only inventory provisioning.
- `POST /api/v1/haven/bookings` — authenticated booking creation; ownership comes from JWT claims.
- `GET /api/v1/haven/bookings` — authenticated caller's bookings only.
- `GET /api/v1/haven/bookings/{bookingID}` — authenticated caller's booking only.
- `POST /api/v1/haven/bookings/{bookingID}/cancel` — caller-owned pending/confirmed booking cancellation.

### Inventory and booking safety

Migration `019_haven_room_inventory.sql` adds date-scoped room inventory. The migration intentionally does not invent room counts for existing hotels. An administrator must provision inventory for every requested night before a booking is accepted. Booking creation locks the relevant inventory rows, verifies capacity for every night, increments reserved inventory and creates the booking in one transaction. Cancellation releases inventory and changes booking state in one transaction.

The existing schema does not define a payment-confirmation workflow for Haven. A created booking remains `pending`; this endpoint does not claim payment success or booking confirmation. Refund coordination is not implemented by this change.

## Vorax endpoints

- `GET /api/v1/vorax/restaurants?city=&cuisine=&limit=` — active restaurant discovery.
- `GET /api/v1/vorax/restaurants/{restaurantID}` — active restaurant detail.
- `GET /api/v1/vorax/restaurants/{restaurantID}/menu` — available menu items.
- `POST /api/v1/vorax/orders` — authenticated order creation with server-side menu pricing, availability checks, restaurant minimum validation and atomic order/item persistence.
- `GET /api/v1/vorax/orders` — authenticated caller's orders only.
- `GET /api/v1/vorax/orders/{orderID}/tracking` — authenticated caller's order status only.

The client cannot set authoritative prices or totals. The server reads current prices from the database and stores the price snapshot in `order_items` in the same transaction as the order. The order is created with `pending` status; payment capture and merchant fulfillment are not implied.

## Module wiring

`cmd/server/main.go` registers both modules with the shared Postgres client and auth service. Public discovery endpoints do not require application JWT authentication. Booking, order, tracking, cancellation and inventory operations are protected by the backend auth middleware. Ownership is derived from the token subject, not request-body user IDs.

## Validation and known limits

- Go source was formatted successfully with `gofmt` (which also checks Go syntax).
- Go package tests could not run in this environment because the module dependencies are not present locally and dependency download did not complete. This is unverified, not a passing test result.
- Database migrations and endpoints have not been exercised against a live PostgreSQL database.
- Consumer app Haven/Vorax list pages now use API-backed repositories and BLoCs. Hotel detail/booking and restaurant menu/order tracking screens no longer use canned demo data; they consume the new endpoints and display honest loading/error/pending states.
- Flutter/Dart tools are not installed in this environment, so consumer-app compilation and widget tests could not be run.
- The HTTP handlers currently contain SQL and need a follow-up refactor into application ports/use cases and infrastructure repositories to complete the desired clean module layering.
- Inventory provisioning is admin-only and requires the new migration to be applied before booking requests can succeed.

## Gateway and migration runner integration

- Kong now routes the implemented Haven booking detail/cancel and Vorax restaurant detail endpoints, plus Haven inventory provisioning.
- Haven/Vorax JWT enforcement is route-scoped: public hotel/restaurant/menu discovery is not made private by a service-wide JWT plugin; booking, inventory, order and tracking routes remain JWT protected. The backend independently checks authentication and caller ownership.
- Added `haven_room_inventory_019_down.sql` as the reviewed rollback file for migration 019. The migration-up file discovery now excludes `*_down.sql` files so rollback SQL cannot be mistaken for an up migration.
