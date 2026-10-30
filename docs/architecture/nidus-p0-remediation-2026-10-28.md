# Nidus P0 remediation record — 2026-10-28

Scope: implement source-level fixes for NIDUS-P0-01 through NIDUS-P0-11 from `nidus-production-readiness-audit-2026-10-28.md`, plus the P1 source continuation recorded below. No tests were added. P0 ride acceptance uses the existing status column and cancel route/reason; the P1 continuation adds canonical Nidus driver document, onboarding, profile, vehicle, and earnings routes required to replace the audit-identified unmounted client calls.

## NIDUS-P0-01 — Driver API contract and registration

Audit Files reconciliation: all five files named in the audit finding were changed as part of the P0-01 fix.

Changed files from the finding's Files list:
- `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart`
- `apps/driver_app/lib/features/auth/data/repositories/auth_repository.dart`
- `services/api/internal/modules/nidus/interfaces/http/router.go`
- `services/api/internal/modules/auth/interfaces/http/handlers.go`

The driver registration request now identifies its role, creates a driver profile transactionally, and returns a driver-role token. The app uses the canonical Nidus paths for ride lifecycle, active ride, profile, stats, and online/offline status. The router mounts those existing contracts. Profile verification remains fail-closed; new drivers cannot go online until verification flags and a vehicle type are present.

## NIDUS-P0-02 — Driver ride BLoC and acceptance UI

Audit Files reconciliation: the single file named in the audit finding, `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart`, was changed. The additional files below support its handlers and acceptance flow.

Changed files:
- `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart`
- `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart`
- `apps/driver_app/lib/features/ride/domain/entities/active_ride.dart`
- `apps/driver_app/lib/features/ride/domain/entities/ride_offer.dart`
- `apps/driver_app/lib/features/ride/domain/usecases/get_active_ride_usecase.dart`
- `apps/driver_app/lib/core/di/injection.dart`

Ride BLoC event handlers are registered; backend errors are surfaced; active rides are recovered through the driver endpoint. The acceptance page loads a server-provided offer instead of constructing a fake trip, and only navigates after acceptance succeeds. Fields absent from the offer contract (rider identity, road distance, ETA) are not fabricated or displayed.

## NIDUS-P0-03 — Driver GPS and matching freshness

Audit Files reconciliation: all five files named in the audit finding were changed.

Changed files from the finding's Files list:
- `apps/driver_app/lib/core/network/location_service.dart`
- `apps/driver_app/lib/features/home/presentation/bloc/driver_home_bloc.dart`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart`
- `services/api/internal/modules/nidus/interfaces/http/handlers/location_handler.go`
- `services/api/internal/modules/nidus/application/services/matching_engine.go`

Location updates are sent through the repository to the existing Nidus location route. The API resolves the authenticated user to the driver profile, updates the authoritative PostgreSQL location and freshness timestamp, then updates the location cache. Matching uses persisted fresh coordinates and filters unverified drivers.

## NIDUS-P0-04 — WebSocket contract and subscriptions

Audit Files reconciliation: the consumer `ride_repository.dart` and the other six client/server files listed in the audit were changed. `services/api/internal/modules/nidus/interfaces/http/handlers/ws_bridge.go` was reviewed but left unchanged because it already emits through the canonical handler message type; the client/server contract fix is implemented at the handler and client boundaries.

Changed files:
- `apps/consumer_app/lib/core/di/injection.dart`
- `apps/consumer_app/lib/core/network/websocket_client.dart`
- `apps/consumer_app/lib/features/auth/presentation/bloc/auth_bloc.dart`
- `apps/consumer_app/lib/main.dart`
- `apps/driver_app/lib/core/network/websocket_client.dart`
- `apps/driver_app/lib/features/auth/presentation/bloc/auth_bloc.dart`
- `apps/driver_app/lib/features/home/data/repositories/driver_home_repository.dart`
- `apps/driver_app/lib/features/home/presentation/bloc/driver_home_bloc.dart`
- `apps/driver_app/lib/main.dart`
- `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart`
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart`
- `services/api/internal/modules/nidus/interfaces/http/handlers/websocket_handler.go`

Both clients and the WebSocket handler now use a versioned (`schema_version: 1`) wire contract, the server's `payload` envelope, and Unix-second timestamps. The server rejects missing or unsupported incoming schema versions; both clients send version 1 and ignore unsupported server messages. They use authenticated connections, restore subscriptions after reconnect, and subscribe to driver offers/ride updates. The driver app wires offer messages into the home BLoC and resolves update notifications by fetching the authoritative ride. `ws_bridge.go` remains unchanged and emits messages through the canonical handler message type.

## NIDUS-P0-05 — Safety features fail closed

Audit Files reconciliation: the two consumer safety files listed in the audit were changed to fail closed. `router.go` and `cmd/server/main.go` were inspected for route composition, but no safety routes were added because the safety backend and operational workflow do not exist; enabling a route without that implementation would be unsafe. `router.go` is changed elsewhere in this P0 patch for the canonical Nidus routes, not to expose safety endpoints.

Changed files from the finding's Files list:
- `apps/consumer_app/lib/features/nidus/data/repositories/safety_repository.dart`
- `apps/consumer_app/lib/features/nidus/presentation/pages/safety_toolkit_page.dart`

SOS, trusted-contact management, and trip sharing no longer call missing endpoints. SOS and trip-sharing controls are visibly unavailable, the repository returns explicit unavailable results/errors, and no `(0,0)` fallback location is sent. The actual safety backend and emergency-response workflow remain unimplemented and must be completed before enabling these controls.

## NIDUS-P0-06 — Ride offer lifecycle and authoritative offer data

Audit Files reconciliation: the single audit-listed acceptance-page file was changed; the additional backend and migration files implement the required server-side lifecycle.

Changed files:
- `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart`
- `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go`
- `services/api/internal/modules/nidus/application/commands/ride_lifecycle.go`
- `services/api/internal/modules/nidus/application/commands/dispatch.go`
- `services/api/internal/modules/nidus/application/commands/auto_matcher.go`
- `services/api/internal/modules/nidus/domain/entities/ride.go`
- `data/migrations/postgres/025_nidus_accepted_ride_state.sql`
- `data/migrations/postgres/025_down.sql`

The existing `matched` state represents an offer; successful acceptance transitions to `accepted`. Assignment accepts a target state so direct acceptance reserves the driver and records acceptance in the same transaction. Matched offers expire after 30 seconds; the matcher returns stale reservations to `searching` and releases the driver. Driver decline uses the existing cancel route with the existing reason field, returns the ride to searching, releases the driver atomically, and records the reason. The partial unique index now includes accepted rides. A matching down migration restores the prior index predicate for a reviewed rollback. The pending-offer screen uses actual server offer data only.

## NIDUS-P0-07 — Nearby driver data

Audit Files reconciliation: the single file named in the audit finding was changed.

Changed files from the finding's Files list:
- `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go`

Hard-coded driver names, ratings, vehicle details, plates, acceptance rates, and trip counts were removed. Values are queried from the persisted driver/user records; unavailable optional values serialize as null. Unverified or non-available drivers are excluded.

## NIDUS-P0-08 — Fare estimate response and units

Audit Files reconciliation: the repository, ride BLoC, and estimate handler named in the audit were changed. `apps/consumer_app/lib/features/nidus/presentation/pages/ride_request_page.dart` was reviewed but left unchanged; the contract/unit correction is handled in the repository and BLoC without inventing new UI fields or routes.

Changed files from the finding's Files list:
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart`
- `apps/consumer_app/lib/features/nidus/presentation/bloc/ride_bloc.dart`
- `services/api/internal/modules/nidus/interfaces/http/handlers/estimate_handler.go`

The client parses the `estimates` envelope and selects the requested ride type (standard by default). Monetary values are consumed in the major currency units returned by the API instead of being divided by 100 a second time. Wheelchair estimates are marked unavailable until accessibility can be verified from persisted vehicle capability data, and requests for that ride type fail transparently.

## NIDUS-P0-09 — Currency consistency

Audit Files reconciliation: the composition root, pricing service, and two driver fare-display files named in the audit were changed. `request_ride.go` and `005_nidus_lifecycle.sql` were reviewed but left unchanged: the fix configures currency and units at the pricing boundary and avoids altering the established ride persistence schema.

Changed files:
- `services/api/cmd/server/main.go`
- `services/api/internal/modules/nidus/application/services/pricing_service.go`
- `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go`
- `apps/driver_app/lib/features/ride/presentation/pages/ride_acceptance_page.dart`
- `apps/driver_app/lib/features/ride/presentation/pages/ride_navigation_page.dart`
- `apps/driver_app/lib/features/home/domain/entities/driver_stats.dart`
- `apps/driver_app/lib/features/home/presentation/widgets/earnings_summary.dart`

Non-development startup requires explicit launch-currency pricing inputs instead of labelling USD defaults as ETB. Fare displays use the server-provided ride currency; driver ledger earnings are summed only from ETB ledger transactions; the driver earnings card uses ETB and does not invent online-hours data. Development may still use the existing USD default tariff configuration.

Required non-development pricing environment variables are `NIDUS_PRICING_{STANDARD,PREMIUM,ELECTRIC,SHARED,WHEELCHAIR}_{BASE_FARE,PER_KM_RATE,PER_MINUTE_RATE,MINIMUM_FARE}`. Base and minimum fares are entered in major currency units; per-distance and per-minute rates are also entered in major units.

## NIDUS-P0-10 — Active ride routes and authorization

Audit Files reconciliation: all five files named in the audit finding were changed, including the consumer repository active-ride path.

Changed files from the finding's Files list:
- `services/api/internal/modules/nidus/interfaces/http/router.go`
- `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go`
- `services/api/internal/modules/nidus/application/queries/get_ride_query.go`
- `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart`
- `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart`
- `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart`
- `apps/driver_app/lib/features/ride/domain/usecases/get_active_ride_usecase.dart`
- `apps/consumer_app/lib/features/nidus/presentation/bloc/ride_bloc.dart`

The rider and driver active-ride routes are mounted. Driver access maps the authenticated user ID to the driver's profile ID before authorization. Active-ride queries include accepted rides, and the driver BLoC rehydrates its current ride on construction.

## NIDUS-P0-11 — Verification and vehicle eligibility

Audit Files reconciliation: the matching engine and driver handler named in the audit were changed. `data/migrations/postgres/001_initial_schema.sql` was reviewed but left unchanged; the existing verification columns are reused, and no unsupported accessibility/capability column was invented.

Changed files from the finding's Files list:
- `services/api/internal/modules/nidus/application/services/matching_engine.go`
- `services/api/internal/modules/nidus/interfaces/http/handlers/driver_handler.go`
- `services/api/internal/modules/nidus/domain/entities/driver.go`
- `services/api/internal/modules/nidus/application/commands/dispatch.go`
- `services/api/internal/modules/nidus/application/commands/auto_matcher.go`
- `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go`
- `services/api/internal/modules/nidus/application/commands/ride_lifecycle.go`
- `data/migrations/postgres/025_nidus_accepted_ride_state.sql`

Drivers must have verified license, background check, inspected vehicle, and a configured vehicle type before going online or being assigned. Matching and atomic assignment share a vehicle/ride compatibility policy. Wheelchair rides remain unavailable because the current schema cannot prove accessibility; no accessibility field was invented.

## Validation and remaining limits

- All 16 existing architecture scripts passed after the changes.
- Go source formatting passed (`gofmt` reports no unformatted Go files).
- No tests were added, per request.
- Go package tests could not reach compilation because dependencies are absent from the local cache and `GOPROXY=off` prevents downloading them.
- Flutter/Dart tooling is not installed in this environment, so Dart formatting, analysis, and compilation remain unverified.
- PostgreSQL migrations (including the new `025_down.sql` rollback), Kafka/WebSocket flows, and rider-to-driver-to-settlement behavior still require runtime validation in an environment with the required dependencies and services.
- Continuation validation on 2026-10-28: all 16 existing `scripts/architecture/*.py` scripts exited successfully, and `gofmt` found no unformatted Go files. A normal targeted `go test` attempt timed out while downloading modules; rerunning with `GOPROXY=off` confirmed required modules are absent from the local cache. Flutter, Dart, PostgreSQL client/server, and Docker/Podman executables are unavailable, so those checks were not claimed as passed.

### Additional continuation validation — 2026-10-28

- All five existing `scripts/migrations/tests/*.sh` checks passed: down-migration rollback safety, atomic migration/ledger handling, payment migration wrapper normalization, migration runner behavior, and payment-integrity preflight. The wrapper-normalization check uses mocked `psql`; these results do not establish live PostgreSQL execution.
- `bash -n` passed for `scripts/migrations/migrate-up.sh`, `scripts/migrations/migrate-down.sh`, and the migration rollback safety check script.
- `unzip -t` passed for the current remediation bundle before repackaging.
- A fresh targeted Go package test attempt from `services/api` again timed out while downloading required modules. Compilation and Go tests therefore remain unverified; no test files were added.
- No Flutter/Dart, PostgreSQL client/server, or Docker/Podman executables are installed in this environment. Mobile analysis and live migration apply/rollback remain release gates.


## Additional source remediation — P1 implementation continuation

The following P1 gaps received additional source changes in the continuation pass. These changes do not supersede the outstanding runtime release gates above.

### Driver onboarding and documents

- Added `data/migrations/postgres/026_driver_documents.sql` and its rollback `data/migrations/postgres/026_down.sql` for private document metadata/content, review audit fields, onboarding decision state, suspension, and appeal state.
- Added `services/api/internal/modules/driver-onboarding/interfaces/http/handlers/documents.go` with authenticated document listing/upload/content/deletion, admin document review, onboarding status, driver appeal submission, and admin approve/reject/suspend decisions.
- Mounted those routes from `services/api/internal/modules/nidus/interfaces/http/router.go` under the existing authenticated Nidus driver route group. Added authenticated profile and vehicle update handlers on the canonical Nidus driver paths; vehicle changes invalidate old registration/insurance/inspection approvals and return the driver to offline/pending review.
- Updated the driver document repository, dependency injection, documents page, onboarding page, and profile repository to submit actual image content, read persisted records, view uploaded content, display review state, submit an appeal, and use canonical Nidus profile/vehicle/document paths. Hard-coded sample document states and false upload-success messages were removed.
- Driver online status, nearby-driver results, pending offers, matching candidates, and atomic assignment now require approved onboarding and current verified license/background/inspection/registration/insurance documents. This is deliberately fail-closed; existing drivers without reviewed records remain ineligible until onboarding is completed. Vehicle edits invalidate prior vehicle-specific approvals and return the profile to offline/pending review.

### Routing, map tiles, navigation and placeholder removal

- Added a Google Routes API client in `services/api/internal/modules/nidus/application/services/routing_client.go`. Pricing and ETA use traffic-aware road distance/duration when configured; non-development startup now requires `GOOGLE_MAPS_ROUTES_API_KEY`. The development fallback ETA reports low confidence and does not claim traffic/weather data.
- `apps/consumer_app/lib/core/map/map_tile_provider.dart` no longer defaults to public OSM tile endpoints. It accepts build-time licensed tile templates and uses cache-only behavior if none are configured. Configuration requirements are documented in `docs/operations/nidus-production-readiness-requirements.md`.
- Driver navigation now opens external turn-by-turn directions to server-provided coordinates and validates coordinates. The initial pass disabled call/chat buttons until real services were wired; the later continuation adds authenticated masked-call and driver-chat actions described below. The driver earnings repository now uses mounted canonical endpoints, the API returns ETB ledger-based period reports and daily breakdowns, and unavailable online-hours/earnings-per-hour values remain unavailable instead of being fabricated. Hard-coded earnings summary samples were removed. Consumer fare estimates/history and the remaining driver ride-request card now display the server-provided currency rather than a hard-coded USD symbol.
- Driver ride completion now uses the active ride returned by the backend, shows the server currency/fare, and navigates only after the BLoC reports completion; fabricated rider, New York route, and USD fare data were removed.
- Driver home notifications/support actions now report that their services are unavailable rather than silently doing nothing. The safety preview/no-op repository no longer fabricates successful SOS or trip-sharing outcomes.

### Code-level validation status

No test files were added. Source formatting and static repository checks are being rerun after these changes. Go compilation remains dependent on unavailable external modules in this environment; Flutter/Dart and PostgreSQL runtime tooling are not installed. The direct emergency-dialer fallback is enabled, but server-side incident delivery, secure public tracking, and trusted-contact notification remain unavailable. Therefore the full P1 audit and production readiness are not closed by this source continuation alone.


### Latest code-level checks — 2026-10-28

- All 16 existing architecture scripts passed.
- All 5 existing migration shell checks passed.
- `gofmt` reports no unformatted Go source; `bash -n` passed for migration up/down scripts.
- Go parser accepted all 242 API Go files with zero syntax parse failures.
- A targeted `go test` cannot type-check or run because required modules are not cached and `GOPROXY=off` disables fetching them. Flutter/Dart and PostgreSQL tools are not installed, so Dart analysis and live SQL execution are not claimed as passed.
- No test files were added.

### Communication and emergency-dialer continuation — 2026-10-28

- The consumer safety toolkit and ride SOS countdown now open the device phone dialer after explicit confirmation. The configured number is `NIDUS_EMERGENCY_NUMBER`; the default is `911`. The user can build with `--dart-define=NIDUS_EMERGENCY_NUMBER=990` only after confirming that 990 is a valid emergency line for the target region. The UI does not claim that responders were notified; the user must confirm the call in the phone app.
- Corrected the SOS countdown text so it no longer claims that emergency responders or trusted contacts were alerted. Failed dialer launches keep a retry path available.
- Added consumer and driver masked-call actions. Each retrieves the active proxy number from the authenticated `/api/v1/telephony/rides/{rideID}/contact` endpoint and launches the phone dialer; neither app falls back to the other participant's real phone number.
- Added the driver-side authenticated chat UI using the existing `/api/v1/chat/rides/{rideId}/messages` contract, server history, send, and read receipt operations. The consumer chat repository now subscribes to the correct WebSocket topic as well as listening for inbound messages. Chat defaults on; masked calling activates when all required Twilio credentials and proxy numbers are configured, unless explicitly disabled.
- Added `docs/operations/nidus-google-maps-to-openstreetmap-transition.md`, listing the application/backend files to migrate, OSM-compatible tile/geocoding/routing options, provider cost/licensing constraints, and ordered migration steps. Added consumer map attribution and fixed the no-tile-provider path so an absent configured provider does not crash when the map tries to access `mirrors.first`.
- Updated feature-flag JSON in both the repository configuration and consumer app assets for chat and masked calling.

### Current validation boundaries

- The 16 architecture scripts and five existing migration checks passed after this continuation; both feature-flag JSON files parse; all 242 Go files pass Go syntax parsing and Go formatting checks.
- Go package compilation remains unverified because module downloads timed out and dependencies are unavailable locally. Dart/Flutter tooling is unavailable, so mobile static analysis and compilation are unverified. No tests were added.
- SOS opens the phone dialer only; it is not a server-side incident dispatch. Secure expiring public trip tracking, trusted-contact notifications, incident persistence/escalation, and operational response procedures remain unimplemented. Masked calling requires real Twilio Proxy credentials, service SID, and a usable proxy-number pool to operate. The OSM document is a transition plan; the driver map and backend routing client have not yet been migrated away from Google providers.
