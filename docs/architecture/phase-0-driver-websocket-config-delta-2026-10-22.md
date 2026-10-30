# Phase 0 — Driver WebSocket endpoint configuration delta (2026-10-22)

## Status

**Source-level defect corrected; Flutter/runtime validation remains pending.** This change aligns the driver app with the existing deployment contract that `WS_BASE_URL` is the complete WebSocket endpoint, including `/ws`.

## Evidence and finding

- `apps/driver_app/Dockerfile` declares `ARG WS_BASE_URL=wss://api.nidaw.com/ws` and passes it to Flutter as `--dart-define=WS_BASE_URL=...`.
- `apps/driver_app/README.md` documents `WS_BASE_URL=ws://localhost:8080/ws`.
- Compose, Kubernetes overlays, and Helm values also provide WebSocket URLs ending in `/ws`.
- Before this change, `apps/driver_app/lib/core/di/injection.dart` configured `WebSocketClient` from `API_BASE_URL`, so the dedicated `WS_BASE_URL` build define was ignored.
- Before this change, the client converted the configured HTTP URL scheme and appended `/ws?type=driver`, deriving a WebSocket endpoint from the API base rather than consuming the dedicated endpoint.
- The consumer app already consumes `WS_BASE_URL` as a complete endpoint. The Go Nidus router registers `GET /ws` in its protected route group; the handler additionally validates the WebSocket token.

## Change

1. Driver dependency injection now reads `WS_BASE_URL`, defaulting to `ws://localhost:8080/ws`.
2. The driver WebSocket client parses that complete URL directly and adds/retains `type=driver` as a query parameter. JWT authentication remains in the `nidaw-auth.<token>` WebSocket subprotocol; the token is not moved into the URL.
3. Added `scripts/tests/driver-websocket-config-test.sh` to verify the build define, runtime define, documented convention, and endpoint construction stay aligned.

No Go route, gateway route, authentication policy, or server behavior was changed. No Kong route change is implied by this fix.

## Validation

- `bash -n scripts/tests/driver-websocket-config-test.sh`: passed.
- `bash scripts/tests/driver-websocket-config-test.sh`: passed.
- Flutter analyzer, Flutter tests, browser handshake, and gateway handshake were not run in this environment; do not treat this static regression test as runtime proof.

## Remaining acceptance work

- Run `flutter analyze` and driver app tests with the declared Flutter toolchain and dependencies available.
- Test driver and consumer handshakes through the selected deployment topology, including missing/invalid/valid tokens and exact upstream URI.
- Continue route-by-route Kong exposure review. Phase 0 remains open.
