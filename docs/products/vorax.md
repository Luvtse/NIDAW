# Vorax — Food Delivery

## Scope

Vorax owns restaurant discovery, restaurant details, menu reads, food-order creation/listing and order tracking.

## Current backend evidence

Implementation is under `services/api/internal/modules/vorax/`. The HTTP router is mounted by the API composition root and exposes `/api/v1/vorax`:

- `GET /restaurants`
- `GET /restaurants/{restaurantID}`
- `GET /restaurants/{restaurantID}/menu`
- protected `POST /orders`
- protected `GET /orders`
- protected `GET /orders/{orderID}/tracking`

The module contains application services, domain order policy and PostgreSQL reader/writer adapters.

## Current client evidence

Consumer app feature code exists under `apps/consumer_app/lib/features/vorax/`.

## Boundaries and limitations

Vorax owns merchant/menu/order lifecycle and delivery coordination state. Payment provider execution and financial settlement belong to shared payment/ledger capabilities. The currently mounted API route list does not by itself prove a full courier dispatch, merchant operations console, real-time delivery network, refunds, commissions, debt recovery or surge-pricing workflow. Those capabilities must be verified in code before being documented as active.
