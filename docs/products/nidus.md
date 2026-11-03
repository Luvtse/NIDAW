# Nidus — Ride-Hailing

## Scope

Nidus owns rider ride requests, fare estimates, dispatch/matching, driver availability, trip lifecycle, ride changes/stops, cancellation, ratings and driver operational workflows.

## Current backend evidence

Implementation is under `services/api/internal/modules/nidus/`. Its router is mounted by `services/api/cmd/server/main.go`. The mounted route families include:

- fare estimate and estimate listing;
- ride create/list, active ride and ride detail;
- accept, start, complete, cancellation quote, cancel and rate;
- cash collection confirmation where enabled;
- destination changes, stop quotes/approval/timers and price extensions;
- split fare operations where configured;
- driver onboarding, document upload/review, profile, vehicle, availability, nearby drivers and earnings;
- rider payment methods and promotions;
- driver location and WebSocket ride communication.

See the source router for exact methods, middleware and conditional route registration.

## Current client evidence

Consumer client feature code: `apps/consumer_app/lib/features/nidus/`. Driver ride workflows: `apps/driver_app/lib/features/ride/` and related home/profile/documents/earnings features.

## Operational requirements

- Production pricing and routing configuration is fail-closed when required pricing configuration or `GOOGLE_MAPS_ROUTES_API_KEY` is missing.
- Routing API keys are server-side secrets and must never be embedded in mobile builds.
- Production map tiles require a licensed or self-hosted tile template configured with build-time `NIDUS_MAP_TILE_PRIMARY_TEMPLATE`; optional fallback uses `NIDUS_MAP_TILE_SECONDARY_TEMPLATE`.
- Driver matching eligibility depends on approved onboarding, configured vehicle type and valid required driver documents.
- Chat requires authenticated ride-participant access. Masked calling requires the configured Twilio service and proxy-number settings.
- Emergency dialer invocation is a user-confirmed device action; it is not automatic emergency dispatch or responder notification.

## Fare integrity contract

The Nidus fare implementation uses integer santim (100 santim = 1 ETB) for monetary calculations. At ride confirmation, the accepted fare is frozen in a `ride_fare_snapshots` record with the original route, contract distance/duration, pricing-rule version, surge, minimum-fare floor and quoted total (`F0`). Ride completion derives the payable amount from that frozen contract; actual trip metrics are operational data and do not silently reprice the accepted fare. Approved destination changes create a new snapshot revision rather than editing frozen values.

Approved stop charges follow the implemented `stops-v1` policy: the fixed stop fee defaults to 1,000 santim (Br 10.00) and can be overridden by `NIDUS_STOP_FEE_SANTIM`; waiting begins at an inclusive 10-minute dwell threshold; the waiting charge is one-half of the original frozen fare (`F0`), with deterministic half-up rounding. The computed stop charge is persisted and carries its policy version.

Only the authenticated rider can approve a stop charge. The approval endpoint accepts no client-supplied amount, and uniqueness on `(ride_id, seq)` prevents duplicate approval. Timer transitions use server timestamps and guarded state updates. Settlement refuses unapproved stop charges and fails closed if the stop-charge dependency is unavailable. Cash and electronic settlement use the same payable formula: `max(0, F0 + S + W - P)`, where `S` is approved stop fees, `W` is persisted waiting charges and `P` is the promotion discount.

Implementation evidence: `services/api/internal/modules/nidus/application/services/final_fare_service.go`, `services/api/internal/modules/nidus/application/services/stop_charge_service.go`, `services/api/internal/modules/nidus/domain/entities/stop_charge.go`, and migrations `027_nidus_fare_snapshot.sql`, `028_nidus_stop_charges.sql`, and `030_nidus_destination_fare_amendments.sql`.

## Limits and status

Nidus is the most extensively implemented product in this repository, but this documentation does not certify production readiness. Review the actual configuration, payment and ledger integration, driver onboarding, routing, safety and incident-handling paths before launch. Durable trip-sharing, trusted-contact acknowledgement and incident escalation must not be advertised as implemented without corresponding backend/provider workflows.
