# API Reference

## Base URL and versioning

The API uses `/api/v1` for versioned product routes. Local development normally exposes the API on port `8080` when using the checked-in Compose development configuration. Production hostnames must come from the deployment environment.

This reference lists mounted route families visible in the current source. It is not a complete OpenAPI specification. Authentication and role requirements must be checked in the router/handler code; protected route groups are marked below.

## Nidus

Router: `services/api/internal/modules/nidus/interfaces/http/router.go`.

- `GET /health`, `GET /ready`
- `POST /api/v1/nidus/rides/estimate`, `GET /api/v1/nidus/rides/estimates`
- Ride operations under `/api/v1/nidus/rides`: create/list/detail/active; accept/start/complete/cancel/rate; cancellation quote; cash collection confirmation; destination change; stop quote/approval/timer; price extension; split operations; email receipt.
- Driver operations under `/api/v1/nidus/drivers`: onboarding, appeal, onboarding decision, document list/upload/content/delete/review, nearby drivers, profile, vehicle, stats, earnings, active/pending rides, online/offline and driver detail.
- Payment methods under `/api/v1/nidus/payment-methods`.
- Promotions under `/api/v1/promotions`.
- Location under `/api/v1/nidus/location`.
- WebSocket under the Nidus router's `/ws` path.

Some routes are conditionally mounted based on dependency/feature configuration. Inspect the router before relying on optional paths.

## Haven

Router: `services/api/internal/modules/haven/interfaces/http/router.go`.

- `GET /api/v1/haven/hotels`
- `GET /api/v1/haven/hotels/{hotelID}`
- Protected: `PUT /api/v1/haven/hotels/{hotelID}/inventory/{date}`
- Protected: `POST /api/v1/haven/bookings`
- Protected: `GET /api/v1/haven/bookings`
- Protected: `GET /api/v1/haven/bookings/{bookingID}`
- Protected: `POST /api/v1/haven/bookings/{bookingID}/cancel`

## Vorax

Router: `services/api/internal/modules/vorax/interfaces/http/router.go`.

- `GET /api/v1/vorax/restaurants`
- `GET /api/v1/vorax/restaurants/{restaurantID}`
- `GET /api/v1/vorax/restaurants/{restaurantID}/menu`
- Protected: `POST /api/v1/vorax/orders`
- Protected: `GET /api/v1/vorax/orders`
- Protected: `GET /api/v1/vorax/orders/{orderID}/tracking`

## Corpus

Router: `services/api/internal/modules/corpus/interfaces/http/router.go`.

- Protected: `POST /api/v1/corpus/bookings`
- Protected: `POST /api/v1/corpus/bookings/{bookingID}/approve`
- Protected: `POST /api/v1/corpus/bookings/{bookingID}/reject`

## Logix

No Logix HTTP router is mounted by the current API composition root. Logix domain and persistence code exists, but no public Logix API should be assumed.

## Other API surfaces

Authentication, ledger, notifications, chat, telephony, legal and payment-related routes are mounted or registered in the server composition in varying ways. Consult their router and handler implementations for exact methods, role requirements and payload schemas before integrating a client.

## Contract changes

When changing an endpoint, update the router, DTOs, client call sites, gateway route if exposed, authorization, tests and this reference. Add an OpenAPI contract only when it is generated/validated against the implementation.
