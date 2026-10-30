# Nidus map-cost transition plan: Google Maps to OpenStreetMap-based services

## Goal

Reduce Google Maps platform charges by using OpenStreetMap (OSM) data and OSM-compatible services for map rendering, geocoding, routing, and navigation. The consumer map widget already uses `flutter_map`, and geocoding already uses Nominatim/Photon. The remaining Google dependency is primarily the backend traffic-aware route provider and the external navigation URL. The current tile layer deliberately requires configured providers rather than sending production traffic to the public OSM tile server by default.

## Important cost and licensing distinction

OpenStreetMap data is openly licensed, but hosted map tiles, geocoding, and routing still consume infrastructure and provider capacity. The public `tile.openstreetmap.org` service is not an unlimited production CDN and must not be treated as one. A sustainable low-cost deployment should either use a commercial OSM-compatible provider within its free tier and terms, or operate a tile/routing stack on infrastructure whose capacity and operational costs are understood. Preserve visible OpenStreetMap attribution and each provider's usage policy. Do not bulk-download public tiles or bypass provider rate limits.

## Target provider choices

- **Map rendering:** keep `flutter_map` and `MapTileProvider`; point the primary tile template to an approved OSM-compatible tile service. Add a secondary provider only when its license and failover terms permit the intended use. For a self-hosted stack, use a maintained tile server and document update/backup procedures.
- **Geocoding and reverse geocoding:** the app already uses Nominatim with Photon fallback and cache. Keep the rate limiter and User-Agent. For production volume, move Nominatim to a self-hosted instance or a contracted provider instead of relying on the shared public endpoint.
- **Route distance and ETA:** replace Google Routes API with a provider adapter for OSRM, Valhalla, or GraphHopper. OSRM is a good first candidate for driving distance/route geometry; it does not provide Google's equivalent traffic-aware live ETA by default. ETA confidence and product wording must reflect the selected engine's actual capabilities.
- **Turn-by-turn navigation:** keep a neutral `geo:`/OSM-compatible URL where supported and provide an explicit OpenStreetMap-based app/web fallback. Do not label an external Google Maps handoff as OSM navigation.
- **Fallback behavior:** when a provider is unavailable, use cached map tiles where possible and show an honest unavailable/degraded state. Never substitute straight-line estimates or claim traffic-aware routing when it was not returned by the provider.

## Ordered migration steps

1. Inventory the deployed Google Maps APIs, billing usage, route requests, navigation handoffs, and all tile/geocoding traffic. Keep a short-term rollback switch while migrating.
2. Select the tile host and route engine. Record terms, attribution requirements, rate limits, coverage, update cadence, availability target, and projected hosting costs.
3. Implement a routing-provider interface and an OSRM/Valhalla/GraphHopper adapter. Keep the existing `RouteResult` contract (`DistanceKm`, `DurationMinutes`, `StaticDurationMinutes`) stable. Add provider configuration such as `NIDUS_ROUTING_PROVIDER`, `NIDUS_ROUTING_BASE_URL`, and any provider-specific secret only where needed.
4. Replace Google Routes initialization in the API composition root. Remove the Google API-key hard requirement only after the alternate provider is wired, configured, and validated in code. Fail clearly when the selected provider is missing; do not silently fabricate routes.
5. Configure `NIDUS_MAP_TILE_PRIMARY_TEMPLATE` and optional secondary template to the chosen OSM-compatible provider. Keep cache and health reporting. Add required attribution in the map UI and provider-specific User-Agent/contact metadata if required.
6. Confirm Nominatim/Photon usage remains rate-limited and cached. For production load, move to hosted or self-hosted geocoding rather than assuming the public Nominatim service is free capacity.
7. Replace the driver app's Google Maps directions URI with a configurable, provider-neutral navigation handoff and OSM-compatible fallback. Ensure coordinate validation and destination semantics stay unchanged.
8. Run code-level compilation and migration-independent static checks; then, when credentials and real services are supplied, test Addis Ababa coverage, route distance/ETA plausibility, geocoding, tile failover, offline cache, and attribution on real devices.
9. Monitor Google billing and traffic for a full release window. Disable unused Google APIs only after confirming no remaining production call sites. Retain rollback configuration until the new stack is stable.

For emergency dialing, the consumer app supports a compile-time `NIDUS_EMERGENCY_NUMBER` override. Its default is `911`; configure `--dart-define=NIDUS_EMERGENCY_NUMBER=990` only if the relevant local authority confirms 990 is an active emergency line for the release region.

## Files to touch

### Required application and backend files

- `apps/consumer_app/lib/core/map/map_tile_provider.dart` — configure primary/secondary OSM-compatible tile templates, cache/fallback behavior, and provider-specific request policy.
- `apps/consumer_app/lib/core/map/live_map_widget.dart` — verify attribution is always visible and tile errors are surfaced; keep the shared map component provider-agnostic.
- `apps/consumer_app/lib/core/geocoding/geocoding_service.dart` — retain or adjust Nominatim/Photon endpoints, User-Agent, rate limiting, caching, and provider failover.
- `apps/consumer_app/lib/core/di/injection.dart` — centralize provider configuration if a routing/geocoding adapter is introduced in the client.
- `apps/consumer_app/lib/features/nidus/presentation/pages/ride_request_page.dart` — confirm pickup/drop-off selection remains compatible with OSM geocoding and server-calculated pricing.
- `apps/consumer_app/lib/features/nidus/presentation/pages/ride_tracking_page.dart` — confirm map routes, driver tracking, and ETA labels use the selected provider's semantics.
- `apps/driver_app/lib/features/home/presentation/widgets/driver_map.dart` — replace the current `GoogleMap` widget and NYC fallback with the shared OSM tile/map component, real driver coordinates, and attribution.
- `apps/driver_app/pubspec.yaml` — remove duplicate `google_maps_flutter` declarations after all imports are migrated; keep or add the compatible `flutter_map`/`latlong2` dependencies used by the replacement component.
- `apps/driver_app/lib/features/ride/presentation/pages/ride_navigation_page.dart` — replace the Google Maps handoff with the chosen OSM-compatible handoff/fallback.
- `services/api/internal/modules/nidus/application/services/routing_client.go` — replace the Google Routes HTTP implementation with the selected OSM-compatible routing provider while preserving the route result contract.
- `services/api/internal/modules/nidus/application/services/pricing_service.go` — retain server-owned distance pricing and make provider failures explicit; verify the actual file/name in the current tree before editing if it differs.
- `services/api/internal/modules/nidus/application/services/eta_service.go` — report ETA confidence based on actual provider data; do not imply traffic awareness when the chosen route engine has no live traffic data.
- `services/api/cmd/server/main.go` — replace Google API-key startup requirements with configuration for the selected routing provider.
- `env.example` — document OSM-compatible tile templates and routing provider settings, and remove Google-only requirements once migration is complete.
- `docs/operations/nidus-production-readiness-requirements.md` — update deployment and provider requirements.

### Conditional files

- Any Android/iOS app configuration required for a selected navigation scheme or deep link.
- `apps/consumer_app/pubspec.yaml` or `apps/driver_app/pubspec.yaml` only if the selected tile/navigation provider requires a new package; the current consumer map is already based on `flutter_map`.
- Deployment manifests, secret definitions, and monitoring dashboards that currently define `GOOGLE_MAPS_ROUTES_API_KEY`.

## Completion criteria

- No runtime route request depends on Google Routes unless explicitly selected as a rollback provider.
- No map tile request defaults to the shared public OSM tile endpoint for production traffic.
- Map attribution is visible and provider terms are followed.
- Route distance, fare calculation, ETA, and map geometry remain contract-compatible and fail honestly.
- The driver app no longer hardcodes a Google Maps handoff as the only navigation option.
- Production costs and rate limits are documented for the chosen tile, geocoding, and routing providers.
