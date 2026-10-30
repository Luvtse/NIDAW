#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/migrations/preflight-payment-integrity.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/psql" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cat > "$PSQL_CAPTURE"
exit "${MOCK_PSQL_EXIT:-0}"
MOCK
chmod +x "$TMP_DIR/psql"
export PATH="$TMP_DIR:$PATH"
export PSQL_CAPTURE="$TMP_DIR/sql.txt"

"$SCRIPT" >"$TMP_DIR/pass.out"
grep -q "duplicate idempotency keys" "$PSQL_CAPTURE"
grep -q "invalid refund totals" "$PSQL_CAPTURE"
grep -q "duplicate pending refunds" "$PSQL_CAPTURE"
grep -q "Payment integrity preflight passed" "$TMP_DIR/pass.out"

# This is a read-only diagnostic; reject accidental data/schema mutation.
if grep -Eiq '^[[:space:]]*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE)[[:space:]]' "$PSQL_CAPTURE"; then
  echo "Preflight SQL must remain read-only." >&2
  exit 1
fi

if MOCK_PSQL_EXIT=3 "$SCRIPT" >"$TMP_DIR/fail.out" 2>&1; then
  echo "Expected preflight to propagate psql failure." >&2
  exit 1
fi

echo "PASS: payment integrity preflight invokes read-only checks and propagates database errors"
