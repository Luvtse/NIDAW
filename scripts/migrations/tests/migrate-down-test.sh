#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MIGRATE_DOWN="$ROOT_DIR/scripts/migrations/migrate-down.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cat > "$TMP_DIR/psql" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PSQL_CALL_LOG:?}"
for arg in "$@"; do
  case "$arg" in
    *"SELECT version, name FROM schema_migrations"*) printf '%s\n' "${MOCK_APPLIED_MIGRATIONS:-}"; exit 0 ;;
  esac
done
exit 0
MOCK
chmod +x "$TMP_DIR/psql"
export PATH="$TMP_DIR:$PATH"
export PSQL_CALL_LOG="$TMP_DIR/psql.log"

# Invalid steps must be rejected before any database call.
if "$MIGRATE_DOWN" --steps '1;DROP TABLE schema_migrations' --force > "$TMP_DIR/invalid.out" 2>&1; then
  echo 'Expected invalid rollback steps to fail closed' >&2
  exit 1
fi
grep -q 'positive integer' "$TMP_DIR/invalid.out"
[[ ! -s "$PSQL_CALL_LOG" ]]

# If the ledger has migrations but no down files exist, preflight must stop before asking for confirmation.
export MOCK_APPLIED_MIGRATIONS='014 | 014_dispatch_integrity'
if "$MIGRATE_DOWN" --steps 1 --force > "$TMP_DIR/no-down.out" 2>&1; then
  echo 'Expected missing rollback files to fail closed' >&2
  exit 1
fi
grep -q 'no down migration exists' "$TMP_DIR/no-down.out"
! grep -q -- '-f ' "$PSQL_CALL_LOG"
! grep -q 'DELETE FROM schema_migrations' "$PSQL_CALL_LOG"

echo 'migration rollback safety tests passed'
