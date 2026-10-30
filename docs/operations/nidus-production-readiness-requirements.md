# Nidus production readiness configuration

The Nidus API intentionally refuses to start outside `development` when either the launch pricing configuration or `GOOGLE_MAPS_ROUTES_API_KEY` is missing. The routing key is a server-side secret and must not be placed in a mobile build.

## Traffic-aware routing

Set `GOOGLE_MAPS_ROUTES_API_KEY` in the API runtime secret store. Restrict the key to the Routes API and the server's egress/network policy. The API uses Google's Routes API with `TRAFFIC_AWARE` routing and requests route distance, traffic-aware duration, and static duration. If the provider is configured but a route request fails, pricing/ETA returns an error rather than silently substituting a confident-looking heuristic.

Development without a route key uses a low-confidence geometric ETA and the legacy road-distance factor. The fallback ETA confidence is `0.35`; it must not be presented as traffic-aware.

## Licensed map tiles

The consumer app no longer defaults to public OpenStreetMap tile servers. Configure a licensed or self-hosted tile endpoint at build time:

- `NIDUS_MAP_TILE_PRIMARY_TEMPLATE`: required production tile URL template with `{z}`, `{x}`, and `{y}` placeholders.
- `NIDUS_MAP_TILE_SECONDARY_TEMPLATE`: optional licensed fallback template with the same placeholders.

Pass these as `--dart-define` values to the consumer Flutter build. Any provider token embedded in a client URL must be a provider-approved public/client token restricted to the app; never embed a server secret. Ensure the provider contract permits the expected volume, caching, attribution, and intended commercial use before rollout. Without configured templates, the app uses cached tiles only and reports unavailable tiles instead of using a public tile server without permission.

## Driver onboarding and documents

Apply migration `026_driver_documents.sql` before deploying the API/mobile changes. Driver documents are stored in PostgreSQL with a 5 MiB per-file limit and accepted PDF/JPEG/PNG signatures. Admins review document submissions and driver onboarding decisions through the protected API. Driver availability and matching require approved onboarding, a configured vehicle type, and valid verified license, background-check, vehicle-inspection, vehicle-registration, and insurance records. Expired or rejected documents do not satisfy eligibility.

The consumer safety toolkit now opens the device phone dialer for the configured emergency number after explicit user confirmation, and the ride SOS countdown opens the same dialer when confirmed. The build-time `NIDUS_EMERGENCY_NUMBER` override is supported; the default is 911 based on current published emergency-number references. Do not override this to 990 without confirming that 990 is an active emergency service number for the deployment region. This is a direct-call fallback, not automatic incident dispatch: the user must confirm the call in the phone app, and Nidus does not claim that responders were notified. Secure expiring trip-share links, trusted-contact notifications/acknowledgement, durable incident records, operational escalation, and an incident runbook still require a real backend/provider workflow before those capabilities can be advertised as active.

## Rider-driver communications

Chat is enabled by default through `FEATURE_CHAT` unless explicitly disabled. It requires authenticated API access and ride-participant authorization; the driver app refreshes the persisted conversation from the server and the consumer app uses the chat WebSocket topic with REST history/send as the source of truth. Keep API traffic on HTTPS and WebSocket traffic on WSS in deployed environments.

Masked calling activates automatically when all of `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TELEPHONY_TWILIO_SERVICE_SID`, and `TELEPHONY_PROXY_NUMBERS` are configured, unless `FEATURE_MASKED_CALLING=false` explicitly disables it. Set `FEATURE_MASKED_CALLING=true` to require the provider configuration at startup. The API fails startup when the feature is explicitly enabled but required credentials or proxy numbers are missing. Mobile apps call only the authenticated proxy-contact endpoint and never receive the other participant's real phone number.

For a lower-cost OSM migration path, see [`nidus-google-maps-to-openstreetmap-transition.md`](nidus-google-maps-to-openstreetmap-transition.md).