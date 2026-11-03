# Security Architecture

## Trust boundaries

NIDAW includes mobile/web clients, Kong gateway configuration, a Go API, PostgreSQL, Redis, Kafka, object storage and external providers. Treat all client input and client-held state as untrusted. Enforce authentication, authorization and resource ownership in the API, not only in the UI or gateway.

## Authentication and authorization

The API composition root initializes the shared authentication service using configured JWT settings. Protected product routes must validate identity and ownership. Administrative ledger endpoints require the relevant administrative role in their handlers. Keep access tokens short-lived, protect refresh tokens, rotate signing secrets and revoke sessions where supported.

## Secrets

- Never commit `.env`, credentials, provider keys, private keys or production certificates.
- Keep server-only keys on the backend/secret manager; do not compile them into Flutter or web assets.
- Use separate credentials for development, staging and production.
- Restrict provider keys by API, origin, IP or network policy where supported.
- Rotate credentials after suspected exposure and audit dependent workloads.

## Data protection

Use TLS for public API/WebSocket traffic and verified TLS for production database connections. Apply least-privilege database roles and service identities. Minimize personal data in logs, traces, analytics and event payloads. Encrypt backups and protect recovery keys separately.

## API and infrastructure controls

Apply rate limits, strict CORS allowlists, request validation, safe error mapping, secure headers and least-privilege network access. Verify Kong route/upstream paths against actual mounted handlers. Restrict admin interfaces, monitoring consoles, object storage and database ports from public access.

## Financial and event security

Payment webhooks must be authenticated/verified, replay-resistant and idempotent. Ledger posting must be auditable and protected against duplicate delivery. Outbox/event consumers must validate schema and ownership. Administrative adjustments require authorization, reason capture and audit logging.

## Mobile and client security

Use platform-secure storage for credentials where implemented. Do not assume a mobile application can keep a server secret. Protect deep links, file uploads and WebSocket sessions. Server-side authorization remains mandatory even if a screen hides an action.

## Security verification

Security controls must be verified against code, infrastructure policy and deployment configuration. A security report or policy document alone is not proof of an enforced control.
