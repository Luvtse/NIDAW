# Haven — Accommodation Booking

## Scope

Haven owns accommodation catalog reads, hotel details, room inventory updates and booking lifecycle operations.

## Current backend evidence

Implementation is under `services/api/internal/modules/haven/`. The HTTP router is mounted by the API composition root and exposes the `/api/v1/haven` family:

- `GET /hotels`
- `GET /hotels/{hotelID}`
- protected inventory update: `PUT /hotels/{hotelID}/inventory/{date}`
- protected booking create/list/detail/cancel operations under `/bookings`

The router uses catalog and booking services with PostgreSQL persistence adapters.

## Current client evidence

Consumer app feature code exists under `apps/consumer_app/lib/features/haven/`.

## Boundaries and limitations

Haven owns hotel inventory and accommodation reservation state. Payment execution belongs to the shared payment capability; corporate policy and approval state belong to Corpus. The presence of catalog, booking and inventory handlers does not establish a complete production hotel supply integration, payment/refund integration, supplier settlement or operational support process. Verify these before commercial launch.
