# Phase 0 Continuation — Deployment and Active-Ride Contract Reconciliation

**Date:** 2026-10-22  
**Status:** Static audit continuation; Phase 0 remains open.  
**Scope:** Verify the latest active-ride client/router trace against source, and refine the canonical deployment-path evidence. No application behavior was changed and no live service was started.

## 1. Active-ride route: source-confirmed findings

| Layer | Evidence | Finding |
|---|---|---|
| Consumer client | `apps/consumer_app/lib/features/nidus/data/repositories/ride_repository.dart`, `getActiveRide()` | Calls `GET /api/v1/nidus/rides/active`; treats any 404 as “no active ride.” |
| Driver client | `apps/driver_app/lib/features/ride/data/repositories/ride_repository.dart`, `getActiveRide()` | Calls legacy `GET /api/v1/rides/active`. |
| Router | `services/api/internal/modules/nidus/interfaces/http/router.go`, protected `/nidus/rides` route group | Registers `GET /` and `GET /{rideID}`; no literal `/active` route is registered in this group. |
| Existing driver handler | `services/api/internal/modules/nidus/interfaces/http/handlers/ride_handler.go`, `GetActiveRide` | Resolves the authenticated user to a driver profile and queries rides assigned to that driver. The source comment documents `/api/v1/nidus/drivers/active-ride`, but this path is not registered in the inspected router. |

### Defects and risks

1. **Rider endpoint absent:** the consumer's `/api/v1/nidus/rides/active` request has no explicit route. The generic `/{rideID}` handler parses the path segment as a UUID, so the request is expected to fail as an invalid ID unless a different deployed router or rewrite changes the path.
2. **Driver endpoint mismatch:** the driver client calls `/api/v1/rides/active`, while the existing handler's documented canonical path is `/api/v1/nidus/drivers/active-ride`; the inspected router does not mount that handler at the documented path.
3. **Database errors can masquerade as “no active ride”:** `GetActiveRide` treats every error from the ride lookup as `404 ACTIVE_RIDE_NOT_FOUND`. The comment says other errors remain server-side, but the implementation does not distinguish `pgx.ErrNoRows` from connection, timeout, or query errors. This can hide an outage from the client and monitoring.
4. **Rider lookup semantics remain unspecified:** an implementation needs a rider-scoped query and an explicit definition of active statuses. Reusing the driver query would risk identity/ownership errors. Do not add the route until the status set, response DTO, multiple-active-row invariant, and error semantics are agreed and tested.
5. **Client fallback can hide failures:** the consumer client converts every 404 to `null`, which is only safe after the route's not-found contract is unambiguous. The driver client wraps all failures into a generic exception, losing structured status information at this repository layer.

### Required resolution sequence

- Add route-level tests proving exact method/path dispatch and middleware coverage.
- Define rider active statuses and the one-active-ride invariant from the domain model/database constraints.
- Correct driver handler error mapping: only “no rows” should become 404; infrastructure/query failures should become 500 (with structured internal logging, no sensitive SQL details returned).
- Add rider-scoped active-ride query/handler only after verifying the existing query/repository abstractions and response contract.
- Choose one canonical driver path; update the client and optionally preserve a temporary, explicitly tested legacy alias if backward compatibility is required.
- Test identity isolation, no active ride, one active ride, inconsistent multiple active rides, database failure, unauthenticated requests, and response DTO compatibility.

## 2. Deployment identity and URI evidence

| Deployment mode | Backend identity/port | Kong implication |
|---|---|---|
| Compose development | Compose service key `backend`; `container_name: nidaw-backend-dev`; backend listens on container port 8080 | Kong config points to `nidaw-backend:8080`. No explicit `nidaw-backend` Compose network alias is declared in the inspected development file. Container name alone is not a safe substitute for the service DNS name across all Compose/network configurations. |
| Compose production | Compose service key `backend`; `container_name: nidaw-backend-prod`; backend listens on container port 8080 | Same `nidaw-backend:8080` Kong target; no matching explicit alias found in the inspected production file. |
| Kubernetes base | Service `nidaw-backend` exposes HTTP port 80 and targets backend container port 8080 | Kong's `nidaw-backend:8080` does not match the Service's declared HTTP port; in-cluster Service clients should use port 80 unless a different Service/overlay is proven. |
| Gateway config | `platform/gateway/kong/kong.yml` gives services a URL ending at `http://nidaw-backend:8080`, a service `path` such as `/api/v1/nidus`, and routes that match full `/api/v1/nidus/...` paths with `strip_path: false` | Suspected URI-prefix duplication must be resolved by Kong's effective URI rules and a request-path test. Static inspection alone does not prove the exact upstream URI. |

Compose mounts `platform/gateway/kong/kong.yml` as the declarative config. The separate `platform/gateway/routes/*.yaml` fragments are not shown being automatically included/merged by the inspected Compose mounts; do not treat those fragments as active Kong configuration without finding the generation/merge step.

## 3. Verification status and reproducible next checks

### Completed in this continuation

- Re-read the exact consumer and driver repository methods.
- Re-read the Nidus Chi route registration and `GetActiveRide` implementation.
- Compared Kong's upstream host/port/path against Compose service keys and Kubernetes Service ports.

### Not run / not established

- No live Compose stack, Kong container, Kubernetes cluster, HTTP request, database query, or broker was run in this environment.
- No `kong config parse` result is available; do not claim the declarative config parses successfully.
- No live route reachability, authorization, or response contract is certified.

### Next validation sequence in a tool-enabled environment

1. Select and document the canonical deployment target for each supported environment (Compose development, Compose production, Kubernetes).
2. Run the matching Compose config render and validate service DNS aliases/ports; run Kong's declarative config parser using the repository's pinned Kong image/version.
3. Inspect the effective Kong route/service configuration and assert the exact upstream URI for representative Nidus paths.
4. Start the selected environment and test `/health` and `/ready` against backend/dependency failures; static Nginx success responses must not be counted as readiness evidence.
5. Generate the effective Chi route registry and compare it to Kong routes and literal/generated client calls.
6. Execute the active-ride route/handler/authorization tests listed above.
7. Record commands, tool versions, environment, outputs, and unresolved failures in the Phase 0 acceptance review.

## 4. Phase decision

**Phase 0 remains open.** This continuation adds source-level evidence and a concrete runtime validation sequence; it does not close deployment, API-contract, security, or build acceptance gates. Do not mark Phase 1 or later phases fully accepted on the basis of this static review. Preserve the five-product scope and do not create empty Haven/Vorax services or alter existing product business logic as a shortcut.
