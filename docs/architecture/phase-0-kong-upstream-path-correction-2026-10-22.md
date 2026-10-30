# Phase 0 — Kong upstream URI correction (2026-10-22)

## Scope

Correct the statically confirmed URI composition issue in `platform/gateway/kong/kong.yml` without changing public API paths, route exposure, authentication plugins, or upstream hostnames.

## Evidence and change

Kong documents `path_handling: v0` as joining service path, route path, and retained request path. With `strip_path: false`, a full public path such as `/api/v1/nidus/rides` is retained; configuring service path `/api/v1/nidus` would prepend that prefix again. See the official [Kong Route documentation](https://developer.konghq.com/gateway/entities/route/).

- Removed the service-level path prefixes from `nidus-service`, `haven-service`, `vorax-service`, and `auth-service`. Their routes already match complete `/api/v1/...` paths and retain them with `strip_path: false`.
- Kept the public WebSocket route `/ws`, but changed its service path to `/api/v1/ws` and set `strip_path: true`. The Go router registers the WebSocket handler at `/api/v1/ws` (inside the `/api/v1` group); this mapping strips the public `/ws` route and applies the backend path once.
- Did not change `health-service`, since its `/health` and `/ready` routes are proxy-level health endpoints and the service has no path prefix.
- Did not change the `nidaw-backend` hostname. Compose/Kubernetes topology still needs a separate canonical-environment decision and runtime connectivity test.
- Did not alter authentication, authorization middleware, or which routes are exposed.

## Validation

`scripts/audit/test-kong-upstream-path-contract.py` parses the YAML and asserts the four full-path services have no service path, their routes preserve full request paths, and the WebSocket public/backend path mapping is explicit. This is a static regression test, not a live Kong proxy test. The configured Kong image/version still needs to validate the declarative schema and runtime forwarded URI.
