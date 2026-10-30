#!/usr/bin/env bash
# Regression: exercise the migration runner's transaction-control normalization
# against the actual payment-integrity migrations, without requiring PostgreSQL.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MIGRATE_UP="$ROOT_DIR/scripts/migrations/migrate-up.sh"
SOURCE_MIGRATIONS="$ROOT_DIR/data/migrations/postgres"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/migrations"
cp "$SOURCE_MIGRATIONS/015_payment_integrity.sql" "$TMP_DIR/migrations/001_payment_integrity.sql"
cp "$SOURCE_MIGRATIONS/016_payment_integrity_base.sql" "$TMP_DIR/migrations/002_payment_integrity_base.sql"

cat > "$TMP_DIR/psql" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
if [[ "$args" == *" SELECT 1; "* ]]; then echo 1; exit 0; fi
if [[ "$args" == *"SELECT to_regclass('public.schema_migrations') IS NOT NULL;"* ]]; then echo t; exit 0; fi
if [[ "$args" == *"SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = "* ]]; then echo f; exit 0; fi
if [[ "$args" == *"SELECT COALESCE(checksum, '') FROM schema_migrations WHERE version = "* ]]; then exit 0; fi
file=""
previous=""
for arg in "$@"; do
  if [[ "$previous" == "-f" ]]; then file="$arg"; fi
  previous="$arg"
done
if [[ -n "$file" ]]; then
  [[ "$args" == *" --single-transaction "* ]] || { echo 'expected --single-transaction' >&2; exit 30; }
  ! grep -Eiq '^[[:space:]]*(BEGIN|START[[:space:]]+TRANSACTION)[[:space:];]' "$file" || { echo 'nested BEGIN remained' >&2; exit 31; }
  ! grep -Eiq '^[[:space:]]*COMMIT[[:space:];]' "$file" || { echo 'nested COMMIT remained' >&2; exit 32; }
  grep -q 'INSERT INTO schema_migrations' "$file"
  grep -q 'CREATE TABLE IF NOT EXISTS transactions' "$file"
  grep -q 'CREATE TABLE IF NOT EXISTS payment_refunds' "$file" || grep -q 'CREATE TABLE IF NOT EXISTS reconciliation_reports' "$file"
  printf '%s\n' "$file" >> "${APPLIED_FILES:?}"
fi
exit 0
MOCK
chmod +x "$TMP_DIR/psql"
export PATH="$TMP_DIR:$PATH"
export APPLIED_FILES="$TMP_DIR/applied-files.log"
MIGRATIONS_DIR="$TMP_DIR/migrations" "$MIGRATE_UP" --environment production --target 002 > "$TMP_DIR/output.log" 2>&1
[[ "$(wc -l < "$APPLIED_FILES")" -eq 2 ]]
grep -q 'Migrations completed: 2 applied' "$TMP_DIR/output.log"
echo 'actual payment migration wrapper normalization tests passed (mocked psql; no PostgreSQL execution)' 
