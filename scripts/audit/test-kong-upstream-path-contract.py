#!/usr/bin/env python3
"""Static regression test for Kong service/route upstream URI composition."""
from pathlib import Path
import sys

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required for this audit test") from exc

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "platform/gateway/kong/kong.yml"

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

try:
    config = yaml.safe_load(CONFIG.read_text())
except Exception as exc:
    fail(f"Kong YAML did not parse: {exc}")

services = {service["name"]: service for service in config.get("services", [])}
for name in ("nidus-service", "haven-service", "vorax-service", "auth-service"):
    service = services.get(name)
    if service is None:
        fail(f"missing service {name}")
    if service.get("path"):
        fail(f"{name} must not prepend a service path to full public API route paths")
    for route in service.get("routes", []):
        if route.get("strip_path") is not False:
            fail(f"{name}/{route.get('name')} must preserve the full API path")

ws = services.get("websocket-service")
if ws is None or ws.get("path") != "/api/v1/ws":
    fail("websocket service must target the backend's mounted /api/v1/ws path")
ws_routes = [r for r in ws.get("routes", []) if r.get("name") == "websocket-connection"]
if len(ws_routes) != 1 or ws_routes[0].get("paths") != ["/ws"] or ws_routes[0].get("strip_path") is not True:
    fail("public /ws route must strip its path and forward to service path /api/v1/ws")

# Documented Kong path_handling=v0 behavior: full route paths are retained
# when strip_path=false; a stripped public /ws is replaced by service.path.
def join_path(service_path: str, request_path: str) -> str:
    parts = [part.strip("/") for part in (service_path, request_path) if part.strip("/")]
    return "/" + "/".join(parts) if parts else "/"

if join_path("", "/api/v1/nidus/rides") != "/api/v1/nidus/rides":
    fail("full API path should reach backend unchanged")
if join_path("/api/v1/ws", "") != "/api/v1/ws":
    fail("WebSocket upstream path should be /api/v1/ws")
print("PASS: Kong service paths preserve full API URIs and map public /ws to backend /api/v1/ws")
