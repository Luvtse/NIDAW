# Phase 0 — Confirmed client/API contract findings

## Scope

This pass compares concrete client call sites against the active Go composition root and route registrations. It is static source evidence; no live API request was made. Findings below distinguish confirmed source mismatches from behavior that still needs runtime confirmation.

## Confirmed findings

| ID | Evidence | Finding | Impact | Safe next action |
|---|---|---|---|---|
| CCF-01 | `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart` calls `/api/v1/rides/{rideId}/accept`, `/start`, `/complete`, `/cancel`, and `/api/v1/rides/active`. The Nidus router registers lifecycle routes under `/api/v1/nidus/rides/{rideID}/...` and has no explicit `/api/v1/rides/*` alias. | Driver app uses legacy paths not registered in the inspected active router. | Driver ride actions can fail at the API boundary unless another mounted router/rewrite handles these paths. No such compatibility path was established in this pass. | Check all routers and gateway rewrites, then align client/server contract with focused tests. Prefer a documented compatibility period if clients are deployed independently. |
| CCF-02 | `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart` calls `GET /api/v1/rides/active`; consumer `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart` calls `GET /api/v1/nidus/rides/active`. Nidus router has `GET /api/v1/nidus/rides/{rideID}` but no literal `/active` handler. `RideHandler.GetRide` parses `rideID` as UUID and returns `400 INVALID_ID` on parse failure. | `/active` is not an active-ride endpoint in the inspected router; it can be interpreted as `{rideID}` and fail UUID parsing. | Both driver and consumer active-ride lookups lack an explicitly registered matching endpoint in this router. | Define intended active-ride semantics and authorization/response shape, then implement and contract-test an explicit route; do not overload the ride-detail handler. |
| CCF-03 | Consumer safety repository documents and uses base `/api/v1/nidus/safety` (`apps/consumer_app/lib/features/nidus/data/repositories/safety_repository.dart`). The inspected Nidus router and `services/api/cmd/server/main.go` do not register a safety route group. | Safety API client calls have no matching route established in the active composition root. | SOS, trip-sharing, and trusted-contact workflows may fail despite UI/repository presence. | Trace any alternate router/service; if none exists, implement the real safety workflow and persistence/authorization before exposing the UI, or make the unavailable state explicit. |
| CCF-04 | At audit time, consumer upload used multipart field `selfie`; server `services/api/internal/modules/selfie/interfaces/http/handlers.go` reads `r.MultipartForm.File["image"]`. | Multipart field-name mismatch was confirmed and is now corrected in the consumer client: it sends `image`, matching the server handler. | Before the client fix, uploads were rejected because the server could not find the expected file part. | Canonical field is `image`; consumer client updated. Add a multipart handler test and client contract test to lock the contract. Avoid accepting arbitrary fields without a documented compatibility policy. |
| CCF-05 | Client posts pre-selfie to `/api/v1/driver/rides/{rideId}/pre-selfie`. `services/api/internal/modules/selfie/interfaces/http/handlers.go` registers exactly `/driver/rides/{rideId}/pre-selfie`; `main.go` mounts it under `/api/v1` behind authentication when `FEATURE_PRE_SELFIE` is enabled. | Route path and authentication mounting are present, conditionally. | Earlier audit wording that implied the upload route itself was absent was too broad; the concrete upload route exists behind the feature flag. | Keep route status conditional in the capability matrix; test flag-on/off behavior and multipart field compatibility. |

## Important non-findings / limits

- The selfie redeem handler registers `GET /api/v1/selfies/{id}` in the same authenticated group. A UI link or route reference alone does not prove successful redemption; participant authorization, expiry, and response handling still need tests.
- Chat is conditionally mounted under `/api/v1/chat` in `main.go` when its feature is enabled. This is different from safety, for which no route group was found in the inspected composition root.
- This document does not establish the behavior of any separate deployment, external gateway rewrite, or alternate binary entry point not inspected here.

## Required contract tests

1. Test active ride retrieval for authenticated rider and driver, no active ride, unauthorized user, and multiple/invalid active associations.
2. Test every driver lifecycle client path against the selected canonical API contract, including ownership and role checks.
3. Test safety endpoints against actual registered handlers and verify no UI action reports success when the backend is unavailable.
4. Test pre-selfie multipart upload with the exact client field name, invalid media, oversized body, wrong participant, expired ride/session, and disabled feature flag.
5. Compare the full client method/path inventory with the mounted router and effective gateway config; test forwarded URI and method in the selected deployment mode.

## Phase 0 status

These findings are concrete source-level defects or gaps, but they do not close Phase 0. The active deployment configuration, runtime routing, full client inventory, and required build/test baseline remain acceptance items. The follow-up fix changed the consumer client's multipart key from `selfie` to the server's existing canonical `image` field. Other findings remain unresolved; this source edit has not yet been validated by Flutter tests or an end-to-end upload.
