#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$ROOT/scripts/audit/generate-kong-exposure-matrix.py" --root "$ROOT"
python3 - "$ROOT" <<'PY'
import csv, sys
from pathlib import Path
root=Path(sys.argv[1])
source=root/'docs/architecture/phase-0-mounted-route-registry-static-2026-10-22.csv'
matrix=root/'docs/architecture/phase-0-kong-exposure-review-matrix-2026-10-22.csv'
with source.open(newline='', encoding='utf-8') as f: src=list(csv.DictReader(f))
with matrix.open(newline='', encoding='utf-8') as f: rows=list(csv.DictReader(f))
assert len(rows)==len(src), f'matrix rows {len(rows)} != source rows {len(src)}'
assert all(row['review_status']=='UNREVIEWED' for row in rows), 'matrix must not imply approval'
assert all(row['method'] and row['effective_path'] and row['owner'] for row in rows), 'required route evidence missing'
assert all(row['review_notes'].startswith('Static candidate only') for row in rows), 'runtime caveat missing'
assert any(row['direct_kong_candidate_routes'] for row in rows), 'expected some direct Kong candidates'
assert any(not row['direct_kong_candidate_routes'] for row in rows), 'expected routes requiring exposure decisions'
print(f'PASS: exposure matrix covers all {len(src)} source routes and keeps every decision explicitly unreviewed')
PY
