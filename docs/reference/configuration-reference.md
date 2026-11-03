# Configuration Reference

## Configuration sources

- Root template: `env.example`.
- Compose interpolation and service environment: `platform/docker/compose/*.yaml`.
- Backend configuration loader: `services/api/internal/shared/config/`.
- Nidus-specific settings are also read in product services and are not necessarily part of the central configuration struct.
- Flutter build-time values are supplied through app build configuration/`--dart-define` where applicable.

`env.example` is a broad template, not a guarantee that every listed variable is consumed by the current API process. Confirm use in code before adding a production secret or assuming a setting changes behavior.

## Local development setup

Copy the template and configure the values required by Compose/setup:

```bash
cp env.example .env
```

At minimum, the base Compose stack requires `MINIO_USER` and `MINIO_PASSWORD`. The development override supplies local PostgreSQL, Redis, Kafka and JWT defaults. Replace placeholders before exposing the stack beyond a trusted local machine.

## Important backend variables evidenced in source

The API's current direct environment reads include:

| Variable | Purpose |
|---|---|
| `GOOGLE_MAPS_ROUTES_API_KEY` | Server-side Nidus Routes API credential |
| `NIDUS_DURATION_RULE_VERSION` | Nidus duration rule selection/versioning |
| `NIDUS_STOP_FEE_SANTIM` | Nidus stop-fee configuration |
| `LEDGER_ESCROW_WINDOW_HOURS` | Ledger escrow window configuration |
| `LEDGER_REBUILD_APPLY` | Controls ledger rebuild application behavior |
| `LEDGER_REPORT_KEY` | Ledger report signing/configuration key |
| `TELEPHONY_TWILIO_SERVICE_SID` | Twilio telephony service |
| `TELEPHONY_PROXY_NUMBERS` | Masked-calling proxy numbers |
| `SELFIE_PUBLIC_BASE_URL` | Public base URL for selfie-related links |
| `SELFIE_SIGNING_KEY` | Selfie link/signature secret |
| `SELFIE_STORAGE_DIR` | Selfie storage location |
| `NOTIFICATIONS_EMAIL_FROM` | Notification email sender |
| `FCM_SERVER_KEY`, `FCM_LEGACY_ENDPOINT` | Push notification integration settings |
| `CHAT_TRANSLATE_ENDPOINT` | Chat translation service endpoint |
| `FRAUD_ML_BASE_URL`, `FRAUD_ML_TOKEN` | Fraud ML integration settings |

Other values are loaded through the central config package; inspect its source for the full typed configuration schema.

## Nidus mobile map configuration

- `NIDUS_MAP_TILE_PRIMARY_TEMPLATE`: licensed/self-hosted primary tile URL template with `{z}`, `{x}`, `{y}` placeholders.
- `NIDUS_MAP_TILE_SECONDARY_TEMPLATE`: optional licensed fallback template.
- `NIDUS_EMERGENCY_NUMBER`: build-time emergency dialer number override.

Do not embed server-only credentials in mobile builds. Confirm tile-provider licensing, attribution, caching and commercial-use terms.

## Production requirements

Use a secret manager or protected runtime secret injection. Set separate values for each environment, enforce TLS, rotate credentials, and do not use the Compose development defaults. Production pricing/routing startup requirements are described in [Nidus](../products/nidus.md).


## Feature flags read by the API

The central config loader currently reads these `FEATURE_*` values (defaults shown in `services/api/internal/shared/config/config.go`):

| Variable | Default |
|---|---:|
| `FEATURE_AUTONOMOUS_VEHICLES` | `false` |
| `FEATURE_DRONE_DELIVERY` | `false` |
| `FEATURE_INTERNAL_LEDGER` | `false` |
| `FEATURE_FEDERATED_LEARNING` | `false` |
| `FEATURE_AR_NAVIGATION` | `false` |
| `FEATURE_VOICE_COMMANDS` | `false` |
| `FEATURE_NOTIFICATIONS` | `false` |
| `FEATURE_CHAT` | `true` |
| `FEATURE_CHAT_TRANSLATION` | `false` |
| `FEATURE_MASKED_CALLING` | auto-detected from required Twilio settings |
| `FEATURE_PRE_SELFIE` | `false` |
| `FEATURE_CASH_PAYMENT` | `false` |
| `FEATURE_PROMOTIONS` | `false` |
| `FEATURE_SPLIT_FARE` | `false` |
| `FEATURE_RIDE_STOP_OVERS` | `false` |
| `FEATURE_PRICE_EXTENSION` | `false` |

Changing a flag can unmount routes or alter workflows at process startup. Verify the exact feature wiring and persisted-data implications before changing a production flag. The JSON registry in `config/feature-flags/flags.json` is a separate checked-in registry; do not assume it overrides the environment-driven backend loader.
