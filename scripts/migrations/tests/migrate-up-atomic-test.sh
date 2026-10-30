#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MIGRATE_UP="$ROOT_DIR/scripts/migrations/migrate-up.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/migrations"
cat > "$TMP_DIR/migrations/001_atomic_probe.sql" <<'SQL'
BEGIN;
CREATE TABLE atomic_probe (id INTEGER PRIMARY KEY);
COMMIT;
SQL

cat > "$TMP_DIR/psql" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PSQL_CALL_LOG:?}"
args=" $* "
if [[ "$args" == *" SELECT 1; "* ]]; then echo 1; exit 0; fi
if [[ "$args" == *"SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001')"* ]]; then echo f; exit 0; fi
file=""
previous=""
for arg in "$@"; do
  if [[ "$previous" == "-f" ]]; then file="$arg"; fi
  previous="$arg"
done
if [[ -n "$file" ]]; then
  [[ "$args" == *" --single-transaction "* ]] || { echo 'migration was not run in a single transaction' >&2; exit 20; }
  ! grep -Eiq '^[[:space:]]*(BEGIN|START[[:space:]]+TRANSACTION)[[:space:];]' "$file" || { echo 'nested BEGIN remained in transaction script' >&2; exit 21; }
  ! grep -Eiq '^[[:space:]]*COMMIT[[:space:];]' "$file" || { echo 'nested COMMIT remained in transaction script' >&2; exit 22; }
  grep -q 'CREATE TABLE atomic_probe' "$file"
  grep -q 'INSERT INTO schema_migrations' "$file"
  cp "$file" "${APPLIED_SQL_CAPTURE:?}"
fi
exit 0
MOCK
chmod +x "$TMP_DIR/psql"
export PATH="$TMP_DIR:$PATH"
export PSQL_CALL_LOG="$TMP_DIR/psql.log"
export APPLIED_SQL_CAPTURE="$TMP_DIR/applied.sql"
MIGRATIONS_DIR="$TMP_DIR/migrations" "$MIGRATE_UP" --environment production --target 001 > "$TMP_DIR/output.log" 2>&1
grep -q 'Migrations completed: 1 applied' "$TMP_DIR/output.log"
grep -q 'INSERT INTO schema_migrations' "$APPLIED_SQL_CAPTURE"
[[ "$(grep -c -- '--single-transaction' "$PSQL_CALL_LOG")" -eq 1 ]]
echo 'atomic migration + ledger test passed'
