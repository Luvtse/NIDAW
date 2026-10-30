#!/usr/bin/env python3
"""Validate the checked-in Grafana dashboard is strict JSON with stable panel IDs."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DASHBOARD = ROOT / "platform/monitoring/grafana/dashboards/nidaw-overview.json"


def main() -> int:
    try:
        payload = json.loads(DASHBOARD.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: Grafana dashboard must be valid JSON: {exc}")
        return 1

    dashboard = payload.get("dashboard")
    if not isinstance(dashboard, dict):
        print("FAIL: expected top-level dashboard object")
        return 1

    panels = dashboard.get("panels")
    if not isinstance(panels, list) or not panels:
        print("FAIL: dashboard must contain a non-empty panels list")
        return 1

    panel_ids = [panel.get("id") for panel in panels if isinstance(panel, dict)]
    if len(panel_ids) != len(panels) or any(not isinstance(value, int) for value in panel_ids):
        print("FAIL: every dashboard panel must have an integer ID")
        return 1
    if len(set(panel_ids)) != len(panel_ids):
        print("FAIL: dashboard panel IDs must be unique")
        return 1

    print(f"PASS: Grafana dashboard is valid JSON with {len(panels)} uniquely identified panels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
