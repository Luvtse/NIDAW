#!/usr/bin/env python3
"""Guard the documented Logix schema-evidence gap until it is resolved."""
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
namespace = runpy.run_path(str(ROOT / "scripts/architecture/inventory-schema-ownership.py"))
report = namespace["build_report"]()
assert "## Logix SQL references without migration evidence" in report
assert "`carriers`" in report, "carriers query must remain visible as unresolved schema evidence"
assert "`customs_declarations`" in report, "customs declaration table needs migration/ownership evidence"
assert "`shipments`" in report, "shipment table needs migration/ownership evidence"
assert "`candidate`" not in report, "CTE alias must not be reported as a missing table"
assert "`skip`" not in report, "SKIP LOCKED clause must not be reported as a table"
assert "`columns`" not in report, "information_schema.columns must not be reported as an application table"
doc = (ROOT / "docs/architecture/logix-load-matching-schema-contract.md").read_text()
assert "Status: unresolved" in doc
assert "do not enable the load-matching workflow in production" in doc
assert "No active runtime call site" in doc
print("PASS: Logix schema evidence gap is visible and guarded; no inferred schema accepted")
