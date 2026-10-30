#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DI="$ROOT/apps/driver_app/lib/core/di/injection.dart"
CLIENT="$ROOT/apps/driver_app/lib/core/network/websocket_client.dart"
DOCKER="$ROOT/apps/driver_app/Dockerfile"
README="$ROOT/apps/driver_app/README.md"

# The driver must consume the dedicated full endpoint, matching the build arg.
grep -Fq "'WS_BASE_URL'" "$DI"
grep -Fq "defaultValue: 'ws://localhost:8080/ws'" "$DI"
grep -Fq 'ARG WS_BASE_URL=wss://api.nidaw.com/ws' "$DOCKER"
grep -Fq -- '--dart-define=WS_BASE_URL=${WS_BASE_URL:-wss://api.nidaw.com/ws}' "$DOCKER"
grep -Fq 'WS_BASE_URL=ws://localhost:8080/ws' "$README"

# The client must use the complete endpoint rather than mutate its scheme/path.
grep -Fq 'final wsUri = Uri.parse(baseUrl).replace(' "$CLIENT"
grep -Fq "'type': 'driver'" "$CLIENT"
grep -Fq "Uri.parse(baseUrl).queryParameters" "$CLIENT"
if grep -Fq "baseUrl.replaceAll('http', 'ws')" "$CLIENT"; then
  echo 'FAIL: driver WebSocket client still derives URL scheme from API URL' >&2
  exit 1
fi
if grep -Fq "Uri.parse('\$wsUrl/ws?type=driver')" "$CLIENT"; then
  echo 'FAIL: driver WebSocket client still appends a duplicate /ws path' >&2
  exit 1
fi

echo 'PASS: driver WebSocket configuration uses WS_BASE_URL as the complete endpoint'
