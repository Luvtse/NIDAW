#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MIGRATE_UP="$ROOT_DIR/scripts/migrations/migrate-up.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/psql" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PSQL_CALL_LOG:?}"
for arg in "$@"; do
  case "$arg" in
    "SELECT 1;") echo 1; exit 0 ;;
    *"to_regclass('public.schema_migrations')"*)
      if [[ "${MOCK_LEDGER_MODE:-empty}" == "drift" || "${MOCK_LEDGER_MODE:-empty}" == "gap" ]]; then echo t; else echo f; fi
      exit 0 ;;
    *"SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001')"*)
      [[ "${MOCK_LEDGER_MODE:-empty}" == "drift" ]] && echo t || echo f
      exit 0 ;;
    *"SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '002')"*)
      [[ "${MOCK_LEDGER_MODE:-empty}" == "gap" ]] && echo t || echo f
      exit 0 ;;
    *"COALESCE(checksum, '') FROM schema_migrations WHERE version = '001'"*) echo mismatched-checksum; exit 0 ;;
    *"SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = "*) echo f; exit 0 ;;
  esac
done
exit 0
MOCK
chmod +x "$TMP_DIR/psql"
export PSQL_CALL_LOG="$TMP_DIR/psql.log"
export PATH="$TMP_DIR:$PATH"

# A production dry-run should list schema migrations, but never seed/fault tables.
"$MIGRATE_UP" --environment production --dry-run > "$TMP_DIR/production.out" 2>&1
grep -q 'DRY RUN: no schema or data changes' "$TMP_DIR/production.out"
! grep -q 'CREATE TABLE\| -f ' "$PSQL_CALL_LOG"
! grep -q '003_seed_data.sql\|017_t5_fault_injection.sql' "$TMP_DIR/production.out"
grep -q 'Would apply:.*016_payment_integrity_base.sql' "$TMP_DIR/production.out"

# A requested target is an upper bound and must not apply later versions.
: > "$PSQL_CALL_LOG"
"$MIGRATE_UP" --environment production --dry-run --target 015 > "$TMP_DIR/target.out" 2>&1
grep -q 'Would apply:.*015_payment_integrity.sql' "$TMP_DIR/target.out"
! grep -q 'Would apply:.*016_payment_integrity_base.sql' "$TMP_DIR/target.out"

# Test-only migrations must be rejected as explicit targets in production.
: > "$PSQL_CALL_LOG"
if "$MIGRATE_UP" --environment production --target 017 > "$TMP_DIR/forbidden.out" 2>&1; then
  echo 'Expected production target 017 to fail closed' >&2
  exit 1
fi
grep -q 'fault-injection-only' "$TMP_DIR/forbidden.out"
[[ ! -s "$PSQL_CALL_LOG" ]]

# Malformed target versions must fail before touching the database.
if "$MIGRATE_UP" --environment production --target xyz > "$TMP_DIR/invalid.out" 2>&1; then
  echo 'Expected malformed target to fail' >&2
  exit 1
fi
grep -q 'three-digit migration version' "$TMP_DIR/invalid.out"
[[ ! -s "$PSQL_CALL_LOG" ]]

# Applied migration checksum drift must stop the runner before any SQL is run.
export MOCK_LEDGER_MODE=drift
if "$MIGRATE_UP" --environment production --dry-run > "$TMP_DIR/drift.out" 2>&1; then
  echo 'Expected applied migration checksum drift to fail closed' >&2
  exit 1
fi
grep -q 'Checksum mismatch for applied migration 001' "$TMP_DIR/drift.out"

# A missing eligible migration before a later applied version must not be silently repaired out of order.
export MOCK_LEDGER_MODE=gap
if "$MIGRATE_UP" --environment production --dry-run > "$TMP_DIR/gap.out" 2>&1; then
  echo 'Expected migration history gap to fail closed' >&2
  exit 1
fi
grep -q 'Migration history gap: 002' "$TMP_DIR/gap.out"

echo 'migration runner tests passed'
