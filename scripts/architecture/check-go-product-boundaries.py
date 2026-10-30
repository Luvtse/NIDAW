#!/usr/bin/env python3
"""Fail CI when one product module imports another product's private package.

This is a deliberately narrow guard: it checks source-to-source Go imports under
internal/modules, not HTTP calls, SQL ownership, dependency injection, or runtime
behavior. Passing it is not proof that all business boundaries are correct.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PRODUCTS = {"nidus", "haven", "vorax", "logix", "corpus"}
IMPORT_RE = re.compile(r'"([^"\n]+)"')


def main() -> int:
    api_root = Path(__file__).resolve().parents[2] / "services" / "api"
    module_file = api_root / "go.mod"
    if not module_file.is_file():
        print(f"ERROR: Go module file not found: {module_file}", file=sys.stderr)
        return 2

    module_match = re.search(r"^module\s+(\S+)\s*$", module_file.read_text(), re.M)
    if not module_match:
        print("ERROR: could not parse module directive in services/api/go.mod", file=sys.stderr)
        return 2
    import_prefix = module_match.group(1) + "/internal/modules/"
    modules_root = api_root / "internal" / "modules"
    implemented = {p.name for p in modules_root.iterdir() if p.is_dir()} if modules_root.is_dir() else set()
    implemented_products = sorted(PRODUCTS & implemented)
    missing_products = sorted(PRODUCTS - implemented)

    violations: list[str] = []
    for source in modules_root.rglob("*.go"):
        relative = source.relative_to(modules_root)
        if not relative.parts:
            continue
        source_module = relative.parts[0]
        if source_module not in PRODUCTS:
            continue
        contents = source.read_text(errors="replace")
        for imported in IMPORT_RE.findall(contents):
            if not imported.startswith(import_prefix):
                continue
            rest = imported[len(import_prefix):]
            target_module = rest.split("/", 1)[0]
            if target_module in PRODUCTS and target_module != source_module:
                violations.append(
                    f"{source.relative_to(api_root)} imports private product package "
                    f"{imported} (source={source_module}, target={target_module})"
                )

    failed = False
    if violations:
        failed = True
        print("FAIL: product module boundary violations:", file=sys.stderr)
        for item in sorted(set(violations)):
            print(f" - {item}", file=sys.stderr)

    if missing_products:
        failed = True
        print(
            "FAIL: required first-class product Go modules are missing: "
            + ", ".join(missing_products),
            file=sys.stderr,
        )
        print(
            "Do not add empty placeholder packages to satisfy this check. "
            "Implement real domain/application behavior or document and approve "
            "an evidence-backed alternate runtime before changing this gate.",
            file=sys.stderr,
        )

    if failed:
        print("Implemented product module directories: " + (", ".join(implemented_products) or "none"))
        print("Scope: direct Go imports plus required product module presence; runtime/data/event boundaries are not verified.")
        return 1

    print("PASS: required product module directories exist and no direct Go imports between product modules were found.")
    print("Implemented product module directories: " + (", ".join(implemented_products) or "none"))
    print("Scope: direct Go imports only; this does not verify routes, data ownership, events, or runtime contracts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
