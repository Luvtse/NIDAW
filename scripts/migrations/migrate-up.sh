#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# NIDAW Database Migration - Up
# Runs all pending database migrations
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

ENVIRONMENT="${ENVIRONMENT:-development}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$(dirname "$0")/../../data/migrations/postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-nidaw}"
DB_USER="${DB_USER:-nidaw}"
DB_PASSWORD="${DB_PASSWORD:-}"
TARGET_VERSION="${TARGET_VERSION:-}"
DRY_RUN="${DRY_RUN:-false}"
LEDGER_PRESENT="false"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run database migrations up.

OPTIONS:
    -e, --environment ENV     Environment [default: development]
    -m, --migrations-dir DIR  Migrations directory
    --target VERSION          Target migration version
    --dry-run                 Show what would be done
    -h, --help                Show this help

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
        -m|--migrations-dir) MIGRATIONS_DIR="$2"; shift 2 ;;
        --target) TARGET_VERSION="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# Set database password
if [[ -n "$DB_PASSWORD" ]]; then
    export PGPASSWORD="$DB_PASSWORD"
fi

# Create migrations tracking table. A dry run must never create or alter it.
create_migrations_table() {
    log_info "Creating migrations tracking table..."
    psql -X -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    checksum VARCHAR(64)
);
EOF
}

check_db_connection() {
    psql -X -At -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT 1;" >/dev/null || { log_error "Cannot connect to database '$DB_NAME' at '$DB_HOST:$DB_PORT'."; exit 2; }
}

ledger_exists() {
    local result
    result=$(psql -X -At -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT to_regclass('public.schema_migrations') IS NOT NULL;") || { log_error "Could not inspect schema_migrations."; return 2; }
    [[ "$(printf '%s' "$result" | tr -d '[:space:]')" == "t" ]]
}

# Return the recorded checksum for one version, or empty when it is not applied.
get_applied_checksum() {
    local version="$1"
    psql -X -At -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT COALESCE(checksum, '') FROM schema_migrations WHERE version = '$version';" | tr -d '[:space:]'
}

is_version_applied() {
    local version="$1"
    [[ "$(psql -X -At -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '$version');" | tr -d '[:space:]')" == "t" ]]
}

# An environment must never silently skip an explicitly requested target.
validate_target() {
    [[ -z "$TARGET_VERSION" ]] && return 0
    [[ "$TARGET_VERSION" =~ ^[0-9]{3}$ ]] || { log_error "Target version must be a three-digit migration version (e.g. 015)."; exit 2; }
    local target_file="$MIGRATIONS_DIR/${TARGET_VERSION}_*.sql"
    compgen -G "$target_file" >/dev/null || { log_error "Target migration $TARGET_VERSION does not exist."; exit 2; }
    case "$TARGET_VERSION" in
        003) case "$ENVIRONMENT" in development|dev|staging|test|ci) ;; *) log_error "Migration 003 is seed data and is not allowed in environment '$ENVIRONMENT'."; exit 2 ;; esac ;;
        017) case "$ENVIRONMENT" in test|ci) ;; *) log_error "Migration 017 is fault-injection-only and is allowed only in test/ci."; exit 2 ;; esac ;;
    esac
}

is_migration_allowed() {
    local filename="$1"
    case "$filename" in
        003_seed_data.sql) case "$ENVIRONMENT" in development|dev|staging|test|ci) return 0 ;; *) return 1 ;; esac ;;
        *_fault_injection.sql) case "$ENVIRONMENT" in test|ci) return 0 ;; *) return 1 ;; esac ;;
        *) return 0 ;;
    esac
}

# Enumerate eligible files in lexical order; ledger state is checked per version,
# not by a single high-water mark, so missing historical versions are not hidden.
get_pending_migrations() {
    local pending_seen=false
    while IFS= read -r migration; do
        local filename version checksum applied_checksum
        filename=$(basename "$migration")
        version=${filename%%_*}
        [[ "$version" =~ ^[0-9]{3}$ ]] || { log_error "Invalid migration filename: $filename"; exit 2; }
        is_migration_allowed "$filename" || continue
        if [[ -n "$TARGET_VERSION" && "$version" > "$TARGET_VERSION" ]]; then continue; fi
        if [[ "$DRY_RUN" == "true" && "$LEDGER_PRESENT" != "true" ]]; then
            printf '%s\n' "$migration"
            continue
        fi
        if is_version_applied "$version"; then
            if [[ "$pending_seen" == "true" ]]; then
                log_error "Migration history gap: $version is recorded as applied after an earlier eligible migration is missing. Restore the missing history or repair the ledger with a reviewed recovery plan."
                exit 3
            fi
            checksum=$(sha256sum "$migration" | awk '{print $1}')
            applied_checksum=$(get_applied_checksum "$version")
            if [[ -n "$applied_checksum" && "$applied_checksum" != "$checksum" ]]; then
                log_error "Checksum mismatch for applied migration $version ($filename). Historical migrations must not be edited; add a forward migration."
                exit 3
            fi
            continue
        fi
        pending_seen=true
        printf '%s\n' "$migration"
    done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -type f ! -name "*_down.sql" | sort)
}

# Apply migration
apply_migration() {
    local migration_file="$1"
    local version
    version=$(basename "$migration_file" | cut -d'_' -f1)
    local name
    name=$(basename "$migration_file" .sql)
    local checksum
    checksum=$(sha256sum "$migration_file" | cut -d' ' -f1)
    
    log_info "Applying migration: $name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would apply: $migration_file"
        return
    fi
    
    # Apply the schema change and its ledger record in ONE transaction. Some
    # historical migrations contain top-level BEGIN/COMMIT statements; strip
    # only those transaction-control lines from a temporary copy so psql's
    # --single-transaction can cover both the migration and ledger insert.
    # The checked-in historical SQL files are never modified.
    local transaction_file
    transaction_file=$(mktemp "${TMPDIR:-/tmp}/nidaw-migration.XXXXXX.sql") || {
        log_error "Could not create temporary migration transaction file."
        exit 2
    }
    if grep -Eiq '^[[:space:]]*(BEGIN|START[[:space:]]+TRANSACTION)[[:space:];]' "$migration_file" \
       && grep -Eiq '^[[:space:]]*COMMIT[[:space:];]' "$migration_file"; then
        awk '{ upper=toupper($0);
             if (upper ~ /^[[:space:]]*(BEGIN|START[[:space:]]+TRANSACTION)[[:space:];]/) next;
             if (upper ~ /^[[:space:]]*COMMIT[[:space:];]/) next;
             print }' "$migration_file" > "$transaction_file"
    else
        cat "$migration_file" > "$transaction_file"
    fi
    cat >> "$transaction_file" <<SQL
INSERT INTO schema_migrations (version, name, checksum)
VALUES ('$version', '$name', '$checksum')
ON CONFLICT (version) DO NOTHING;
SQL

    if ! psql -X -v ON_ERROR_STOP=1 --single-transaction -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$transaction_file"; then
        rm -f "$transaction_file"
        log_error "Migration or migration-ledger write failed; transaction rolled back: $name"
        exit 1
    fi
    rm -f "$transaction_file"

    log_success "Migration applied atomically: $name"
}

main() {
    [[ -d "$MIGRATIONS_DIR" ]] || { log_error "Migrations directory not found: $MIGRATIONS_DIR"; exit 2; }
    case "$ENVIRONMENT" in development|dev|staging|production|prod|test|ci) ;; *) log_error "Unknown environment '$ENVIRONMENT'."; exit 2 ;; esac
    validate_target
    command -v psql >/dev/null 2>&1 || { log_error "psql is required to run migrations."; exit 2; }
    command -v sha256sum >/dev/null 2>&1 || { log_error "sha256sum is required to verify migration checksums."; exit 2; }

    log_info "Running database migrations up..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Database: $DB_NAME @ $DB_HOST:$DB_PORT"

    check_db_connection
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: no schema or data changes will be made."
        if ledger_exists; then
            LEDGER_PRESENT="true"
        else
            LEDGER_PRESENT="false"
            log_info "Migration ledger not present; treating all eligible migrations as pending."
        fi
    else
        create_migrations_table
        LEDGER_PRESENT="true"
    fi

    local pending_list
    pending_list=$(get_pending_migrations) || { log_error "Could not calculate pending migrations safely."; exit 3; }
    local -a pending_migrations=()
    if [[ -n "$pending_list" ]]; then mapfile -t pending_migrations <<< "$pending_list"; fi
    local pending_count=0 migration version
    for migration in "${pending_migrations[@]}"; do
        [[ -n "$migration" ]] || continue
        apply_migration "$migration"
        pending_count=$((pending_count + 1))

        if [[ -n "$TARGET_VERSION" ]]; then
            version=$(basename "$migration" | cut -d'_' -f1)
            if [[ "$version" == "$TARGET_VERSION" ]]; then break; fi
        fi
    done
    
    if [[ $pending_count -eq 0 ]]; then
        log_info "No pending migrations"
    else
        log_success "Migrations completed: $pending_count applied"
    fi
}

main "$@"
