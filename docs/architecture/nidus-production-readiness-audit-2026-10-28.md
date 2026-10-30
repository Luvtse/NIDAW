# Nidus Production-Readiness Audit — 2026-10-28

## Scope and verdict

Reviewed the Nidus backend module, rider Flutter app, driver Flutter app, shared networking, route composition, PostgreSQL migrations, matching/pricing/location logic, safety surfaces, and available tests in the repository snapshot used for the 2026-10-28 audit.

**Verdict: NOT production-ready.** This is not primarily a missing-feature-count problem. Several existing UI flows are disconnected from the backend or have incompatible contracts. The most serious issues affect driver onboarding, dispatch/location, live updates, safety, fare estimates/currency, and ride-state recovery. A production pilot should not start until the P0 items below are fixed and verified end-to-end.

Evidence limitation: Go tests could not compile because dependencies were not available in the local module cache and `GOPROXY=off` prevented fetching them. Flutter/Dart tooling is not installed in this environment, so mobile analysis and tests were not executed. Findings below are source-level findings, not claims that live production infrastructure was tested.

## P0 — release blockers

### NIDUS-P0-01 — Driver app API contract does not match mounted backend routes

**Files**
- `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart:25-91`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart:23-73`
- `apps/driver_app/lib/features/auth/data/repositories/auth_repository.dart:49-55, 85-112`
- `services/api/internal/modules/nidus/interfaces/http/router.go:445-570`
- `services/api/internal/modules/auth/interfaces/http/handlers.go:155-205`

**Evidence / impact**
- Driver ride calls use `/api/v1/rides/{id}/accept|start|complete|cancel` and `/api/v1/rides/active`; the Nidus router mounts lifecycle actions under `/api/v1/nidus/rides/{rideID}/...`.
- Driver home/profile/earnings/documents calls use `/api/v1/drivers/...`; no corresponding driver router is registered in `main.go` or the Nidus router. The Nidus router only exposes `/api/v1/nidus/drivers/nearby`, `/pending-rides`, and `/{driverID}` plus `/api/v1/nidus/location/...`.
- The backend has `RideHandler.GetActiveRide`, documented for `/api/v1/nidus/drivers/active-ride`, but it is not registered in the router.
- Registration in `auth/interfaces/http/handlers.go` creates a `users` row with role `rider` regardless of the driver's requested `role`; no driver profile is created. The driver app then calls a missing `/api/v1/drivers/profile` endpoint.

**Required fix**
Choose one canonical API contract, register and authorize all required driver endpoints, implement driver profile creation/onboarding, and add contract tests that compare every app repository endpoint to the actual mounted route table. Do not add route aliases without deciding the canonical path.

### NIDUS-P0-02 — Driver ride BLoC never registers its event handlers

**File**
- `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart:108-125`

**Evidence / impact**
The constructor ends after `super(const ActiveRideInitial())` and does not register `on<AcceptRideRequested>`, `on<StartRideRequested>`, `on<CompleteRideRequested>`, `on<RideUpdated>`, or `on<ClearActiveRide>`. Handler methods exist below but are never connected to the event stream. Driver accept/start/complete UI events therefore do not reach those methods.

**Required fix**
Register every supported event in the constructor and add BLoC tests proving each event causes the expected repository call and state transition.

### NIDUS-P0-03 — Driver GPS is effectively a no-op, and dispatch reads a different source of truth

**Files**
- `apps/driver_app/lib/core/network/location_service.dart:61-79`
- `apps/driver_app/lib/features/home/presentation/bloc/driver_home_bloc.dart:176-225`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart:45-66`
- `services/api/internal/modules/nidus/interfaces/http/handlers/location_handler.go:60-143`
- `services/api/internal/modules/nidus/application/services/matching_engine.go:187-202`

**Evidence / impact**
- `LocationService.updateLocation` only prints coordinates and returns; it does not call the repository or backend.
- `DriverHomeBloc` invokes this no-op. The separate `DriverHomeRepository.updateLocation` method is not called from that path and sends a `location_update` WebSocket message, but the server WebSocket handler only handles `subscribe`, `unsubscribe`, and `ping`.
- The REST location handler expects JSON keys `lat` and `lng`, whereas the unused driver repository sends `latitude` and `longitude` inside a WebSocket `data` envelope.
- The mounted location handler writes to Redis using the authenticated **user ID** as `DriverID`; matching queries `drivers.current_lat`, `drivers.current_lng`, and `drivers.last_location_update` by **driver profile ID**. No source-level `UPDATE drivers SET current_lat/current_lng/last_location_update` was found in the Nidus location path.
- The matcher requires a fresh `last_location_update`, so the current driver app flow cannot make a driver eligible through the inspected code.

**Required fix**
Implement one authenticated location ingestion path, resolve user ID to driver profile ID, validate and persist the latest point/freshness consistently, update the spatial index/cache, and wire the driver app to it. Add stale-location, duplicate-ping, permission-denied, offline, background/resume, and matching-eligibility integration tests.

### NIDUS-P0-04 — WebSocket authentication and message envelopes are incompatible

**Files**
- `apps/consumer_app/lib/core/di/injection.dart:172-180`
- `apps/consumer_app/lib/main.dart:24-30`
- `apps/consumer_app/lib/core/network/websocket_client.dart:90-105, 150-185, 226-246`
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart:1398-1425`
- `apps/driver_app/lib/core/network/websocket_client.dart:20-105`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart:53-73`
- `services/api/internal/modules/nidus/interfaces/http/handlers/websocket_handler.go:100-115, 285-345`
- `services/api/internal/modules/nidus/interfaces/http/handlers/ws_bridge.go:90-165`

**Evidence / impact**
- The consumer app calls `connect()` at startup, but DI does not pass a token provider to `WebSocketClient`; the server requires a token during the handshake.
- Flutter sends WebSocket messages with top-level `data`; Go unmarshals `payload`. Subscription requests therefore arrive without the `topic` the server expects.
- Go server messages serialize `payload` and an integer Unix-seconds `timestamp`; the consumer parser expects `data` and parses `timestamp` as an ISO string. Consumer ride subscriptions receive `message.data`, which is null for the server's envelope.
- The driver app has a WebSocket client but the inspected driver app startup/DI path does not call `connect()`; its home repository listens for `ride_request`, while the bridge broadcasts `notification_inbox` for the `driver:offers` topic. No driver offer subscription is wired.

**Required fix**
Define a single versioned wire schema (including timestamp format and envelope), align both clients and server, inject the token provider, connect/disconnect with auth lifecycle, restore subscriptions after reconnect, and test subscribe/authorize/broadcast/reconnect flows with real JSON fixtures.

### NIDUS-P0-05 — Safety UI calls endpoints that are not implemented/mounted

**Files**
- `apps/consumer_app/lib/features/nidus/data/repositories/safety_repository.dart:211-255, 258-390`
- `apps/consumer_app/lib/features/nidus/presentation/pages/safety_toolkit_page.dart:45-66, 110-170`
- `services/api/internal/modules/nidus/interfaces/http/router.go:408-570`
- `services/api/cmd/server/main.go` (no Nidus safety router registration found)

**Evidence / impact**
The app calls `/api/v1/nidus/safety/sos`, `/share-links`, and `/contacts`, but there is no corresponding backend safety route/module in the inspected route composition. These actions will return not-found rather than alerting emergency contacts or creating a live share link. The safety page also substitutes `(0,0)` when it has no live location, despite the user-facing text implying it shares current location.

**Required fix**
Do not expose SOS/trip-sharing as available until there is a persisted incident workflow, trusted-contact management, delivery/acknowledgement semantics, authorized expiring share tokens, live location sourcing, audit trail, failure escalation, and tested operational procedures. Never send `(0,0)` as a location fallback; require a real current/last-known fix and clearly label its age.

### NIDUS-P0-06 — Driver acceptance screen uses fabricated ride and rider data

**File**
- `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart:59-80, 128-145`

**Evidence / impact**
The screen constructs a hard-coded New York ride, rider name/phone/rating, coordinates, distance, and `$15.50` fare. Its 30-second timeout only pops the screen; it does not call a server-side decline/expire operation or release/reassign an offer. This is unsafe for a real dispatch product and undermines trust.

**Required fix**
Load the authoritative offer by ID, display only server-returned values and currency, and implement a server-side offer lifecycle (offered, accepted, declined, expired, reassigned) with atomic reservation and timeout handling.

### NIDUS-P0-07 — Nearby-driver endpoint returns fabricated identity/vehicle attributes

**File**
- `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go:121-134`

**Evidence / impact**
`GetNearbyDrivers` hard-codes `FullName: "Driver"`, rating `4.8`, vehicle `sedan` / `Toyota Camry`, plate `ABC123`, acceptance `95.0`, and `1250` rides. Those values are not sourced from the actual driver record. If shown to users, this can misrepresent a driver's identity, vehicle, and trust indicators.

**Required fix**
Join the authoritative driver/user/vehicle records and return nullable fields when unavailable. Add tests proving missing data stays missing rather than being fabricated.

### NIDUS-P0-08 — Fare estimate client and server disagree on response shape and money units

**Files**
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart:565-579, 1303-1328`
- `apps/consumer_app/lib/features/nidus/presentation/bloc/ride_bloc.dart:1536-1565`
- `apps/consumer_app/lib/features/nidus/presentation/pages/ride_request_page.dart:424-440, 636-646, 724-733`
- `services/api/internal/modules/nidus/interfaces/http/handlers/estimate_handler.go:113-160`

**Evidence / impact**
- The ride-request page dispatches `GetFareEstimate`; the repository expects a direct `FareEstimate` object with `base_fare`/`total_fare` at the top level.
- The backend estimate handler returns an envelope `{ "estimates": [...] }`, including for the POST `/rides/estimate` fallback. The parser therefore cannot read the expected top-level fields and the BLoC emits `ESTIMATE_FAILED`.
- The server converts internal cents into currency units before returning the estimate (`estimate_handler.go:130-149`), while `FareEstimate.fromJson` divides the response values by 100 again. Fixing only the envelope would risk a 100x underquote unless the units are corrected at the same time.

**Required fix**
Choose one response contract: either a single typed estimate or an estimate-list envelope. Define money units explicitly at the API boundary (recommend decimal major units plus ISO currency for JSON, or integer minor units plus currency), remove duplicate conversion, and add golden contract tests using the actual handler response.

### NIDUS-P0-09 — Pricing currency is configured as USD while ride/ledger assumptions are ETB

**Files**
- `services/api/cmd/server/main.go:116`
- `services/api/internal/modules/nidus/application/services/pricing_service.go:36-90, 242-294`
- `services/api/internal/modules/nidus/application/commands/request_ride.go:267-292`
- `data/migrations/postgres/005_nidus_lifecycle.sql:20-32`
- `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart:128-145`
- `apps/driver_app/lib/features/ride/presentation/pages/ride_navigation_page.dart:35-48`

**Evidence / impact**
The composition root constructs `DefaultPricingConfig()`, whose default currency is `USD` and whose rates are described as dollars. `RequestRideHandler` persists the estimate's currency explicitly, so the migration's ETB column default does not override it. The lifecycle migration says ride currency and ledger rails are ETB, while driver navigation hard-codes `ETB` and the acceptance placeholder hard-codes `$`. This can cause incorrect display and financial settlement assumptions.

**Required fix**
Before real payments, define supported launch currencies and minor-unit rules end-to-end. Configure pricing from environment/region or a persisted tariff table; reconcile estimate, ride, receipt, promo, cancellation, tip, cash, and ledger units; add ETB-specific rounding/settlement tests. Do not simply change the label.

### NIDUS-P0-10 — No active-ride route is mounted for either client

**Files**
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart:1444-1460`
- `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart:64-72`
- `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go:574-619`
- `services/api/internal/modules/nidus/application/queries/get_ride_query.go:263-272`
- `services/api/internal/modules/nidus/interfaces/http/router.go:445-513`

**Evidence / impact**
Both clients call active-ride endpoints, but neither `/api/v1/nidus/rides/active` nor `/api/v1/nidus/drivers/active-ride` is registered. A `GetActiveRide` handler exists but is not mounted. Cold-start recovery after app kill/restart therefore cannot use the intended endpoint. There is a second identity defect: even if the driver handler were mounted, it passes the authenticated user ID to `GetRideQuery`, whose `hasAccess` compares that value directly with `rides.driver_id` (the driver profile ID), so driver access can be denied unless those unrelated IDs happen to match.

**Required fix**
Register correctly scoped rider and driver active-ride queries, ensure each query returns the correct participant DTO, and test 404/no-active, one-active, terminal, and unauthorized-participant cases.

### NIDUS-P0-11 — Matching does not enforce product/vehicle eligibility or driver verification

**Files**
- `services/api/internal/modules/nidus/application/services/matching_engine.go:126-169, 187-202`
- `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go:176-233`
- `data/migrations/postgres/001_initial_schema.sql` (driver verification columns default false)

**Evidence / impact**
Candidate selection fetches available drivers by status, fresh location, and distance. It does not filter candidates by requested ride type, wheelchair-accessible equipment, premium/electric vehicle eligibility, or `license_verified`, `background_check`, and `vehicle_inspected`. The availability transition does not check those verification flags. A `wheelchair`, `premium`, or `electric` option is therefore not guaranteed to receive a matching vehicle/driver.

**Required fix**
Add explicit server-side eligibility policies and verification gates before online status/matching; persist normalized vehicle capabilities; reject impossible ride types transparently. Test every ride type against verified/unverified and compatible/incompatible driver profiles.

## P1 — significant production gaps after P0

### NIDUS-P1-01 — Driver onboarding and account lifecycle are not implemented end-to-end
- `services/api/internal/modules/driver-onboarding/application/commands/verify_document.go` is the only file under the driver-onboarding module; no HTTP router or persistence workflow is registered.
- `apps/driver_app/lib/features/auth/data/repositories/auth_repository.dart` expects a driver profile after registration/login, while the backend auth registration path creates a rider user.
- `apps/driver_app/lib/features/documents/data/repositories/document_repository.dart:12-64` calls document endpoints that are not registered. `apps/driver_app/lib/features/documents/presentation/pages/documents_page.dart:156-167` also has viewer/upload TODOs.

Add driver application, document upload/storage, verification review, vehicle/insurance checks, approval/rejection, expiry, suspension, and appeal workflows. Keep the driver ineligible until verified.

### NIDUS-P1-02 — Driver navigation and ride communications are placeholders
- `apps/driver_app/lib/features/ride/presentation/pages/ride_navigation_page.dart:20-25, 105-135` renders `Map View (Integrate Google Maps)` and has nonfunctional Call/Message buttons.
- `apps/driver_app/lib/features/home/presentation/pages/driver_home_page.dart` has notification/support TODOs.

Implement a real route/navigation provider, safe rerouting, pickup/dropoff arrival confirmation, rider contact through masked calling/chat, and error/low-network states.

### NIDUS-P1-03 — No road-network routing or live traffic model
- `services/api/internal/modules/nidus/application/services/pricing_service.go:229-237` prices with Haversine distance multiplied by a fixed 1.3 road factor and heuristic duration.
- `services/api/internal/modules/nidus/application/services/eta_service.go:45-90, 97-140` uses distance multipliers and time-of-day heuristics; weather and real-time traffic are TODO/no-op.

For competitive ETA, pickup matching, arrival windows, and fair pricing, use a routing/directions matrix with traffic-aware ETA, route distance, road restrictions, map-matched GPS, and measured prediction error. Label estimates honestly until that exists.

### NIDUS-P1-04 — Default map tile providers are not production suitable
- `apps/consumer_app/lib/core/map/map_tile_provider.dart:73-95` uses public OpenStreetMap and OSM France tile endpoints and explicitly says production must replace them.

Choose a licensed provider or operate a compliant tile service; configure quotas, attribution, caching, outage fallback, and monitoring. Verify routing/geocoding licensing separately.

### NIDUS-P1-05 — Driver offer/dispatch model needs a single authoritative lifecycle
- `services/api/internal/modules/nidus/application/commands/auto_matcher.go:110-174` and `services/api/internal/modules/nidus/application/commands/dispatch.go:148-199` automatically reserve a driver and set the ride to `matched` before the driver app accepts.
- `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go:1255-1311` returns all unassigned pending rides to any authenticated driver with a driver profile; the current client does not call this feed.
- `ws_bridge.go` sends only a ride ID to the shared `driver:offers` room, while the driver app has no working subscription/offer flow.

Decide whether the product uses offer-and-accept or immediate assignment followed by acknowledgement. Implement offer expiry, decline, reassignment, cancellation propagation, duplicate suppression, and per-driver eligibility/targeting consistently. Do not reserve a driver indefinitely because a push was missed.

### NIDUS-P1-06 — Safety/trip-sharing is not just an API TODO; the operational system is absent
- Besides the missing endpoints in P0-05, the public URL is hard-coded as `https://nidus.app/track/$token` in `safety_repository.dart`; the actual public tracking page/domain/deployment was not found in the inspected app surfaces.
- A real emergency workflow needs durable incident records, contact delivery, retry/acknowledgement, location freshness, responder escalation, abuse controls, and auditable incident resolution.

Do not market SOS as operational until the backend, delivery providers, public tracker, runbooks, and failure drills are complete.

### NIDUS-P1-07 — Limited Nidus mobile test coverage
- Only two rider Nidus Flutter tests were found: `apps/consumer_app/test/features/nidus/data/ride_eta_dto_test.dart` and `apps/consumer_app/test/features/nidus/presentation/ride_bloc_eta_test.dart`.
- No `apps/driver_app/test` files were found.
- No runnable end-to-end contract suite covers mobile → HTTP/WS → DB → outbox → consumer.

Add rider/driver unit, widget, repository contract, and integration tests for booking, dispatch, state transitions, GPS, reconnect, money, safety, cancellation, and recovery.

## P2 — competitive edge and operational maturity

1. **Reliable dispatch:** offer timeout/reassignment, batching, cancellation propagation, supply forecasting, fairness, service zones, airport/venue pickup rules, driver acceptance/completion metrics, and dispatch experiments.
2. **Real ETA and price confidence:** routing matrix, traffic-aware pickup/dropoff ETA, confidence calibration, actual-versus-predicted monitoring, route-based fare estimates, tolls/wait time/stopovers, and transparent surge rationale.
3. **Trust and safety:** verified driver identity and vehicle, pickup PIN/OTP, masked calling, SOS, trusted contacts, trip sharing, incident workflow, emergency escalation, fraud detection, and support case tracking.
4. **Driver economics:** accurate ETB earnings, commission breakdown, cash reconciliation, payouts, tax statements, destination filters where legal, driver incentives, and clear dispute handling.
5. **Local-market advantage:** Amharic/Oromo/English parity across all ride screens and notifications; low-bandwidth/offline recovery; local payment rails; cash handling; address landmarks and geocoding tuned to Ethiopian addresses; accessibility that is actually backed by fleet supply.
6. **Reliability and abuse controls:** idempotency keys for ride requests and payment-affecting actions, rate limits, replay protection, GPS spoofing/anomaly detection, fraud/risk signals, API SLOs, queue lag alerts, and graceful degraded states.
7. **Growth and retention:** scheduled rides, repeat destinations, family/business profiles, transparent receipts, loyalty/referrals, accessibility, customer support, driver retention metrics, and privacy-safe experimentation. Build only after the core trip lifecycle is trustworthy.

## File-by-file disposition summary

| File / area | Finding | Priority |
|---|---|---|
| `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart` | Event handlers not registered | P0 |
| `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart` | Hard-coded fabricated ride details; timeout has no server transition | P0 |
| `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart` | Wrong paths, missing active route, response DTO mismatch | P0 |
| `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart` | Calls unmounted APIs; incompatible WebSocket location/offer protocol | P0 |
| `apps/driver_app/lib/core/network/location_service.dart` | GPS upload is a no-op | P0 |
| `apps/driver_app/lib/core/di/injection.dart` / driver startup | WebSocket not connected by app lifecycle | P0 |
| `apps/driver_app/lib/features/auth/data/repositories/auth_repository.dart` | Expects absent driver profile APIs | P0 |
| `services/api/internal/modules/auth/interfaces/http/handlers.go` | Registration forces role `rider`; no driver profile creation | P0 |
| `services/api/internal/modules/nidus/interfaces/http/router.go` | Driver/safety/active-ride endpoints missing from router | P0 |
| `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go` | Nearby endpoint fabricates identity, vehicle, rating, history | P0 |
| `services/api/internal/modules/nidus/interfaces/http/handlers/location_handler.go` | Cache keyed by user ID; no DB freshness update | P0 |
| `services/api/internal/modules/nidus/application/services/matching_engine.go` | Requires DB GPS freshness but no compatible writer; no vehicle/verification filters | P0 |
| `apps/consumer_app/lib/core/di/injection.dart` | WebSocket token provider omitted | P0 |
| `apps/consumer_app/lib/core/network/websocket_client.dart` | `data`/`payload` and timestamp contract mismatch | P0 |
| `services/api/internal/modules/nidus/interfaces/http/handlers/websocket_handler.go` / `ws_bridge.go` | Server expects `payload`; driver offer message differs from client expectation | P0 |
| `apps/consumer_app/lib/features/nidus/data/repositories/safety_repository.dart` | Calls safety endpoints not implemented | P0 |
| `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart` | Estimate envelope/unit mismatch; active route missing | P0 |
| `services/api/internal/modules/nidus/interfaces/http/handlers/estimate_handler.go` | Returns list envelope and currency units; client expects single object/minor units | P0 |
| `services/api/internal/modules/nidus/application/services/pricing_service.go` / `cmd/server/main.go` | USD default conflicts with ETB lifecycle/ledger assumptions | P0 |
| `apps/driver_app/lib/features/ride/presentation/pages/ride_navigation_page.dart` | Map and contact actions are placeholders | P1 |
| `apps/driver_app/lib/features/documents/data/repositories/document_repository.dart` | Document endpoints absent | P1 |
| `services/api/internal/modules/driver-onboarding/application/commands/verify_document.go` | No complete onboarding route/persistence lifecycle | P1 |
| `services/api/internal/modules/nidus/application/services/eta_service.go` | Time heuristics, no live traffic/weather | P1 |
| `apps/consumer_app/lib/core/map/map_tile_provider.dart` | Public tile endpoints are explicitly not production-ready | P1 |
| `apps/consumer_app/test/features/nidus/*` / driver tests | Test coverage far below release confidence | P1 |

## Recommended implementation order

1. **Freeze scope and add contract tests first:** route manifest, DTO fixtures, WebSocket wire fixtures, money-unit fixtures.
2. **Make driver accounts usable:** driver onboarding/profile/verification, API paths, registered routes, active ride recovery.
3. **Make dispatch work:** GPS write path, DB/cache identity consistency, eligibility gates, offer lifecycle, driver app event handlers.
4. **Restore real-time flow:** authenticated WebSocket connection, shared envelope, subscriptions, reconnect and replay handling.
5. **Correct fare/currency:** estimate contract, ETB/USD policy, receipt and ledger reconciliation.
6. **Implement safety backend before advertising safety UI:** SOS, contacts, sharing, public tracking, notifications, operational escalation.
7. **Replace placeholders and production map dependencies:** real driver navigation, masked contact/chat, licensed tiles/routing.
8. **Run automated validation:** Go tests, Flutter analyze/tests, PostgreSQL migrations, integration tests for rider→dispatch→driver→completion→settlement, and failure/restart drills.
9. **Pilot gates:** no fake data, zero P0 findings, all core journey tests green, observable error rates/latency, rollback plan, support and incident runbooks.

## Final recommendation

Nidus has a meaningful set of domain code and rider-side screens, but the inspected repository is currently a **prototype/under-development integration**, not a production-ready Uber-class ride-hailing system. Fix the P0 defects before spending effort on advanced differentiators. Competitive advantage comes first from a ride that can be requested, assigned to a verified and compatible driver, tracked live, navigated accurately, paid in the correct currency, recovered after failures, and supported safely.
