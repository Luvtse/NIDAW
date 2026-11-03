# Authentication, Security & Driver Substitute — Implementation Map

Authoritative implementation map for the NIDAW authentication, session-security, and
driver-substitute roadmap. Produced from direct inspection of the repository (backend,
migrations, both Flutter apps). This document is a living implementation reference:
each phase updates the corresponding section rather than spawning new documents.

Status legend: **Reuse** = already production-shaped, keep as-is · **Modify** = existing
file that must change · **New** = genuinely required new file/artifact · **Missing** =
feature absent from the codebase today.

---

## 1. Backend — Auth module

### Existing surface (verified)

| Artifact | Status | Notes |
|---|---|---|
| `services/api/internal/modules/auth/interfaces/http/handlers.go` (571 ln) | Modify | Handlers: `Login` (L91), `Register` (L157), `Refresh` (L252), `GetCurrentUser` (L344), `Logout` (L389), `UpdateProfile` (L467), `ChangePassword` (L521). Email/password only; email + password mandatory in Register. |
| `.../auth/interfaces/http/router.go` | Modify | `NewRouter(db, authService, logger)`; public `/api/v1/auth/login|register|refresh`; protected group (`authService.Middleware()`): `/me`, `/logout`, `/profile`, `/change-password`. Global rate limit 60/min. Mounted at `cmd/server/main.go:198`. |
| `services/api/internal/shared/auth/jwt_middleware.go` (434 ln) | Reuse | Canonical `Claims`, `TokenPair`, `Service`: `GenerateTokenPair` (L148), `ValidateAccessToken/RefreshToken`, `Middleware()`, `RequireRole`, context getters. |
| `services/api/internal/shared/auth/token_store.go` (135 ln) | Reuse+Extend | Redis rotation store: `MarkRefreshUsed`, `RevokeJTI/IsRevoked`, `SetUserFamily/GetUserFamily/RevokeUserFamily`. Wired in `main.go:139` from `redisCache.RawClient()`. Ephemeral only — no persistent device-session record. |
| `services/api/internal/shared/auth/token_service.go` (207 ln) | Consolidate | Parallel `TokenService` duplicating `Service`. Do not extend; converge on `Service`. |
| `cmd/server/main.go` | Modify | Auth wiring L103–140, mount L198; notification service constructed L366 (`MultiProviderNotificationService`). OTP routes need SMS sender + Redis injected through `NewRouter`. |

Config (`internal/shared/config`): `JWT_SECRET` (≥32 chars enforced in prod), `ACCESS_TOKEN_TTL`
(default 15m), `REFRESH_TOKEN_TTL` (default 7d), issuer/audience. New env keys required for OTP
(see §10).

### Gaps vs. roadmap

- **Missing**: any OTP capability — `grep -rni "otp" services/api/internal` yields zero real hits
  (only unrelated matches: ledger `ErrTopupNotPending`, payment `ErrRefundNotPossible`,
  test helpers). Phone-first auth does not exist server-side.
- **Missing**: phone-only registration/login — blocked by schema (§4: `users.email` and
  `users.password_hash` are `NOT NULL`).
- **Missing**: persistent device-session records (listing / revocation / revoke-all / lost-device
  recovery). Rotation state lives only in Redis TTL keys.
- **Missing**: account-enumeration protection. Current `Register` maps duplicate-key errors to
  `EMAIL_EXISTS`-style messages, revealing existing accounts.
- **Bug**: `isDuplicateKeyError` in `handlers.go` compares exact strings and will miss real pgx
  `*pgconn.PgError` (SQLSTATE 23505) values — fix while adding phone upserts.
- **Contract drift**: consumer app calls `GET /api/v1/auth/onboarding-status` and
  `POST /api/v1/auth/onboarding/complete`
  (`apps/consumer_app/lib/features/auth/data/repositories/auth_repository.dart:357,370`) —
  neither route exists in the backend router. Implement or repoint.

## 2. SMS / notifications provider (OTP delivery target)

- `services/api/internal/shared/integrations/notifications/service.go` — **Reuse**.
  `NotificationService.SendSMS(ctx, *SMSRequest)` (interface L15, struct L20);
  `MultiProviderNotificationService` (L57) with failover: `TwilioProvider`
  (AccountSID/AuthToken/FromNumber, L195) → SNS fallback. Constructed in `main.go:366`.
- `internal/modules/telephony/` — Twilio Proxy per-ride privacy-number call sessions.
  **Unrelated to OTP; do not reuse or duplicate.**

## 3. Rider legal consent

- `internal/modules/legal/application/services/consent_service.go` — **Reuse** unchanged:
  `GetActiveDocument`, `GiveConsent` (stores version + timestamp + IP/UA/device),
  `updateConsent`; typed errors `ErrConsentRequired`, `ErrConsentAlreadyGiven`.
- Routes via `legalhttp.RegisterConsentRoutes(r, ...)` (`main.go:201–204`).
- Seeded documents: `terms_of_service`, `privacy_policy`, `cookie_policy`, `driver_terms` v1.0.0
  (`data/migrations/postgres/003_seed_data.sql`). Rider activation hook after OTP verify +
  consent is the only new integration point.

## 4. Database (`data/migrations/postgres/`, latest number 030)

Verified current state:

- `001_initial_schema.sql`: `users` — `email VARCHAR(255) UNIQUE NOT NULL` (L12),
  `phone VARCHAR(20) UNIQUE NOT NULL` (L13), `password_hash VARCHAR(255) NOT NULL` (L15),
  `email_verified BOOLEAN DEFAULT FALSE` (L18), role, status; indexes on email/phone (L25–26).
  `drivers` (L33) FK→users. `legal_documents` (L271), `user_consents` (L292,
  UNIQUE(user_id, document_id)), `consent_audit_log` (L316).
- `026_driver_documents.sql`: `drivers.onboarding_status` CHECK
  ('pending','approved','rejected','suspended'), suspension/appeal columns,
  `driver_documents` table + review-queue indexes. Down-file convention: `NNN_*_down.sql`.

Required new migrations (next free numbers ≥ 031, each with a down file):

| Migration | Content | Status |
|---|---|---|
| `031_phone_identity` | `users.email` → nullable, `users.password_hash` → nullable, add `phone_verified_at TIMESTAMPTZ`; backfill-safe (`ALTER COLUMN ... DROP NOT NULL` preserves data). Guard against conflicting identities via existing UNIQUE(phone). | New |
| `032_device_sessions` | Persistent session table: id, user_id, family_id, refresh_token_hash (SHA-256), rotated_from, device_name/platform, push metadata?, created_at, last_used_at, expires_at (idle+absolute), revoked_at, revoke_reason. Indexes: user_id, family_id, unique partial on active hash. | New |
| `033_driver_substitutes` | Relationship table: primary_driver_id, substitute_user_id, vehicle association, permissions (JSONB/text[] explicit set), status ('invited','pending_primary_confirmation','pending_substitute_confirmation','active','expired','suspended','revoked'), mutual confirmation timestamps, valid_from/valid_until, created/updated. Uniqueness: one active relationship per (primary, substitute, vehicle). | New |

OTP challenges, attempt counters, resend cooldowns: **Redis only** (ephemeral, TTL'd) —
per roadmap §Phase 10; no Postgres OTP tables.

## 5. Driver onboarding & approval

- `internal/modules/driver-onboarding/interfaces/http/handlers/documents.go` — **Reuse**:
  upload/list/review/delete of `driver_documents` (types: drivers_license,
  vehicle_registration, insurance, background_check, vehicle_inspection, profile_photo),
  SHA-256 content hash, expiry auto-expire logic.
- `application/commands/verify_document.go` — **Reuse**: `VerifyDocumentHandler`,
  `DocumentVerificationService` port.
- Routes mounted inside Nidus router (`router.go` L541–549): `/nidus/drivers/onboarding`,
  `/appeal`, `/{driverID}/onboarding/decision`, `/documents*`.
- **Modify (small)**: driver self-registration via phone/OTP must create/link the `drivers`
  row with `onboarding_status='pending'` (as email Register already does) — OTP success must
  never set 'approved'. Add cross-check of `users.status` (suspended/restricted) at Go Online.

## 6. Nidus availability & matching authorization

- `nidus/interfaces/http/handlers/driver_handler.go` `GoOnline` (L503–538+) — **Reuse+Extend**:
  already enforces `onboarding_status='approved'` AND `license_verified` AND
  `background_check` AND `vehicle_inspected` AND verified unexpired `driver_documents` rows
  AND vehicle configured, before setting `status='available'`.
- `nidus/application/services/matching_engine.go` (~L198–210) — **Reuse+Extend**: candidate
  query re-enforces `status='available' AND onboarding_status='approved'` + document EXISTS
  checks.
- **Missing**: substitute-aware dispatch — nothing associates a ride assignment with an active
  substitute relationship or verifies the acting driver's identity against it. Extend
  `GoOnline`/matching to accept substitute relationships (§4 migration 033) and record the
  actual acting driver on assignments.
- Revocation safety: on relationship suspend/expiry/revocation, force offline unless on an
  active trip (complete-or-handover policy enforced server-side).

## 7. Driver substitute — net-new (verified absent)

`grep -rn "substitut"` across Go code returns only incidental comments
(`ws_bridge.go:31`, `cancellation_policy.go:75`, `contractual_duration_service.go:66`);
zero SQL references. No entity, table, handler, or route exists.

New files inside the Nidus module (preserve boundaries — substitute management belongs to
Nidus, not Auth):

| New artifact | Purpose |
|---|---|
| `nidus/domain/entities/substitute.go` | Relationship aggregate + status machine + permission enum |
| `nidus/application/services/substitute_service.go` | Invite, mutual confirmation, activation gating (independent OTP + documents + licence/background/vehicle checks), expiry/suspension/revocation, notification of changes |
| `nidus/interfaces/http/handlers/substitute_handler.go` | REST endpoints under `/api/v1/nidus/drivers/substitutes*` (mounted in nidus `router.go` guarded like SplitSvc pattern) |
| Migration `033_driver_substitutes` | See §4 |

Invariants: substitute has own account/tokens/biometric gate; never inherits wallet, earnings,
profile, or permissions; server authorizes the actual driver per operation.

## 8. Flutter — Consumer App (`apps/consumer_app/lib/features/auth/`)

Existing: `data/repositories/auth_repository.dart` (email/password login L~24/register L~172
incl. `phone` field in register payload, token storage, `refreshAccessToken`, plus the two
nonexistent onboarding endpoints at L357/L370), `presentation/bloc/auth_bloc.dart`
(CheckAuthStatus/LoginRequested/RegisterRequested/Logout/TokenRefresh…), pages:
`login_page.dart` (Email+Password TextFormFields), `register_page.dart`,
`legal_consent_page.dart`, `onboarding_consent_page.dart`. Core modules available for wiring:
`core/network`, `core/di`, `core/startup`, `core/router`. Storage: Hive
(`hive ^2.2.3`, `hive_flutter ^1.1.0`; no `flutter_secure_storage`).

Changes:

| Item | Status |
|---|---|
| Phone-entry + OTP verification pages/widgets | New |
| Repository methods: requestOtp/resendOtp/verifyOtp/phoneLogin | New |
| Bloc events/states for OTP flow, consent-after-verification, skip-optional-profile | Modify |
| Login page switch to phone-first (keep email/password as secondary once set) | Modify |
| Secure refresh storage (encrypted box / platform keystore strategy) | Modify |
| Biometric local gate (`local_auth` — currently absent from pubspec) | New |
| Account & session security settings screen (device list, revoke, revoke-all) | New |
| Wire onboarding-status endpoints to real backend contract | Modify |

## 9. Flutter — Driver App (`apps/driver_app/lib/features/auth/`)

Existing: `data/repositories/auth_repository.dart` (`login(email,password)` L27 → POST
`/api/v1/auth/login`, `register(data)` L62; Hive `Box` via `_getAuthBox()`),
`presentation/bloc/auth_bloc.dart`, pages `login_page.dart`, `register_page.dart`,
`onboarding_page.dart`; domain `entities/driver.dart`, usecases login/register. Other
features: documents, earnings, home, profile, ride. Core: `network/api_client.dart`,
`websocket_client.dart`, `di`, `startup`, `router`.

Changes: phone+OTP flow (new repo methods/pages, Modify bloc), approval-status UI reflecting
`onboarding_status` + document states (Reuse documents feature), biometric gate before
protected functions/going online (`local_auth`, New), substitute invitation/confirmation
management UI (New feature folder under `features/substitutes` calling §7 endpoints),
session/device security screens (New).

## 10. Configuration additions (env)

New keys consumed by OTP service (documented later in
`docs/reference/configuration-reference.md`): `OTP_TTL_SECONDS` (challenge expiry),
`OTP_RESEND_COOLDOWN_SECONDS`, `OTP_MAX_ATTEMPTS`, `OTP_MAX_REQUESTS_PER_HOUR`,
`OTP_HMAC_SECRET` (≥32 chars, distinct from JWT secret), `SMS_OTP_TEMPLATE` optional.
Session policy: `SESSION_IDLE_TIMEOUT`, `SESSION_ABSOLUTE_TIMEOUT` aligned with
`REFRESH_TOKEN_TTL`.

## 11. Documentation consolidation targets (final state, not phase reports)

- `docs/security/security-architecture.md` (37 ln, sections: Trust boundaries, Authentication
  and authorization, Secrets, Data protection, API and infrastructure controls, Financial and
  event security, Mobile and client security, Security verification) — fold in OTP design,
  session persistence, biometrics-as-local-gate, substitute identity rules.
- `docs/security/security-policies.md` — OTP abuse limits, rotation/reuse detection policy.
- `docs/architecture/api-and-event-contracts.md`, `docs/reference/api-reference.md` — new
  `/api/v1/auth/otp/*`, phone login, `/auth/sessions/*`, `/nidus/drivers/substitutes/*`.
- `docs/architecture/database-and-data-ownership.md` — migrations 031–033 ownership.
- `docs/reference/configuration-reference.md` — §10 env keys.
- `docs/operations/*` — Redis dependency for OTP, provider failure handling.

## 12. Execution order & dependencies

1. **Migrations 031–033** (unblock everything else; reversible, preserve data).
2. **OTP service + handlers/routes** (Phase 2) — depends on Redis (`sharedcache.RedisCache`)
   and `MultiProviderNotificationService`; wire deps into `authhttp.NewRouter` in `main.go`.
3. **Phone-first login/register + activation** (Phases 2–3) incl. enumeration-neutral errors,
   fixed `isDuplicateKeyError`, consent integration (Reuse §3), implement missing onboarding
   endpoints (§1).
4. **Driver registration path** (Phase 4) — Reuse §5; guarantee OTP ≠ approval.
5. **Device sessions** (Phase 5) — table 032 + store + rotation lineage + list/revoke routes;
   converge `token_service.go` duplication onto `Service`.
6. **Biometrics** (Phase 6) — client-only, `local_auth` in both apps; no server templates.
7. **Substitutes** (Phase 7) — §7 new files + notifications.
8. **Availability/authorization integration** (Phase 8) — §6 extensions.
9. **Recovery controls** (Phase 9) — rides on 2/3/5.
10. **Flutter integration** (Phase 11) — can start UI shells after step 3 contracts freeze.
11. Verification & doc consolidation (Phase 12 / §11).

## 13. Baseline health

- `go build ./...` → passes (Go 1.19.8, module `nidaw-backend`).
- `go vet ./internal/modules/auth/... ./internal/shared/auth/...` → clean.
- Working tree clean at audit time (single grafted commit `b9d8893`).
