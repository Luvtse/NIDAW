#!/usr/bin/env python3
"""Generate a conservative, source-derived Kong exposure review matrix.

This is deliberately not a Kong router emulator: it only labels direct literal
or regular-expression method/path candidates. Runtime route precedence,
prefix matching, plugins, service-path composition, and deployed configuration
must be validated with the selected Kong version.
"""
from __future__ import annotations
import argparse, csv, re, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required to parse Kong declarative YAML", file=sys.stderr)
    raise SystemExit(2)


def kong_routes(config):
    result = []
    for service in config.get("services", []) or []:
        for route in service.get("routes", []) or []:
            methods = route.get("methods") or ["ANY"]
            paths = route.get("paths") or []
            for method in methods:
                for path in paths:
                    result.append({
                        "service": service.get("name", ""),
                        "service_path": service.get("path", ""),
                        "route": route.get("name", ""),
                        "method": method.upper(),
                        "path": path,
                        "strip_path": route.get("strip_path", True),
                    })
    return result


def direct_match(method, path, kr):
    if kr["method"] not in ("ANY", method.upper()):
        return False
    pattern = kr["path"]
    try:
        if pattern.startswith("~"):
            return re.search(pattern[1:], path) is not None
    except re.error:
        return False
    # Exact literal only; prefix semantics intentionally left to runtime tests.
    return pattern.rstrip("/") == path.rstrip("/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args()
    root = args.root
    source = root / "docs/architecture/phase-0-mounted-route-registry-static-2026-10-22.csv"
    kong_path = root / "platform/gateway/kong/kong.yml"
    out = root / "docs/architecture/phase-0-kong-exposure-review-matrix-2026-10-22.csv"
    with source.open(newline="", encoding="utf-8") as f:
        mounted = list(csv.DictReader(f))
    with kong_path.open(encoding="utf-8") as f:
        routes = kong_routes(yaml.safe_load(f) or {})
    fields = ["method", "effective_path", "owner", "registration_source", "auth_scope", "mount_condition", "notes", "direct_kong_candidate_routes", "direct_kong_candidate_services", "review_disposition", "review_status", "review_notes"]
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for item in mounted:
            matches = [r for r in routes if direct_match(item["method"], item["effective_path"], r)]
            if matches:
                disposition = "Existing Kong route candidate; verify exposure and upstream URI"
                names = ";".join(sorted({m["route"] for m in matches}))
                services = ";".join(sorted({m["service"] for m in matches}))
            elif item.get("auth_scope", "").lower() in ("module-local", "internal", "internal-only"):
                disposition = "Treat as internal until an owner explicitly approves gateway exposure"
                names = services = ""
            elif item.get("mount_condition", "").lower() not in ("always", ""):
                disposition = "Feature/mount-gated; confirm flag, client contract, and exposure before publishing"
                names = services = ""
            else:
                disposition = "Owner decision required: public gateway, internal-only, feature-gated, or unsupported"
                names = services = ""
            row = {k: item.get(k, "") for k in fields[:7]}
            row.update({"direct_kong_candidate_routes": names,
                        "direct_kong_candidate_services": services,
                        "review_disposition": disposition,
                        "review_status": "UNREVIEWED",
                        "review_notes": "Static candidate only; do not treat as approved policy or proof of runtime reachability."})
            writer.writerow(row)
    print(f"Wrote {len(mounted)} route review rows to {out.relative_to(root)}")
    print(f"Kong route method/path entries inspected: {len(routes)}")

if __name__ == "__main__":
    main()
