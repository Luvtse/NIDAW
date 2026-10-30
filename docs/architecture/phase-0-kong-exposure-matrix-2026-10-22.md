# Phase 0 — Kong exposure review matrix (2026-10-22)

## Status

**Draft review artifact only. No exposure decision is approved by this file.** The matrix exists to make route-by-route review explicit and repeatable before anyone changes gateway reachability.

## Artifacts

- Source-derived input: `phase-0-mounted-route-registry-static-2026-10-22.csv` (79 method/path records).
- Generated review matrix: `phase-0-kong-exposure-review-matrix-2026-10-22.csv` (one row per source record).
- Generator: `scripts/audit/generate-kong-exposure-matrix.py`.
- Regression check: `scripts/audit/tests-kong-exposure-matrix.sh`.

Regenerate from the repository root with:

```bash
python3 scripts/audit/generate-kong-exposure-matrix.py
bash scripts/audit/tests-kong-exposure-matrix.sh
```

The generator requires PyYAML to parse `platform/gateway/kong/kong.yml`.

## What the matrix records

Each row preserves the mounted method, effective path, owning module, registration source, observed auth scope, mount condition, and source notes. It adds direct Kong method/path candidates, service names, a conservative review disposition, and `review_status=UNREVIEWED`.

The current static pass produced 12 direct method/path candidates and 67 rows without a direct literal/regex candidate. These counts are specific to this deliberately conservative algorithm. They are not equivalent to the previous 65-record review queue: the earlier comparison used different matching logic. Kong prefix matching, route priority, plugins, service-path composition, deployment overlays, and actual reachability are not emulated here.

## How to review

For every row, an accountable route/product owner must select one of:

- `public-through-gateway` — external clients intentionally reach the handler through the canonical gateway, with handler-level authorization still required where appropriate;
- `internal-only` — no public Kong exposure; identify the intended internal caller/path;
- `feature-gated` — exposure is conditional on a documented feature flag and mounted handler;
- `unsupported-in-this-deployment` — clients must not rely on this route in the selected composition.

Record the selected value, reviewer, evidence, and test reference in a reviewed copy or add reviewed columns under change control. Do not mark a row approved merely because a route is present in Kong or a client contains a URL literal. `Public` in the `auth_scope` column means the handler's observed auth scope, not an automatic decision that the route must be internet-facing.

## Guardrails and open questions

- Keep feature/mount-gated endpoints out of a published route set unless the selected deployment actually wires the handler and documents the flag.
- Retain JWT or other handler authorization for routes that need it; Kong exposure is not an authorization substitute.
- Resolve service path plus route path behavior against the selected Kong version by asserting the exact upstream URI in an integration test.
- Resolve `/ws` versus the mounted `/api/v1/nidus/ws` registration before changing the WebSocket route.
- Confirm the intended identifier formats for regex routes against domain validation.
- Reconcile Haven/Vorax gateway declarations against actual active composition; do not create placeholder handlers.

## Acceptance

The matrix is complete as a static review scaffold, but its decisions remain unreviewed. It does not close Phase 0, establish runtime reachability, or authorize gateway configuration changes.
