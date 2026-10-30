#!/usr/bin/env python3
"""Static regression checks for explicit Corpus outbox event contract versions."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
checks = {
    "version migration": ROOT / "data/migrations/postgres/022_corpus_outbox_contract_version.sql",
    "event bus version fields": ROOT / "services/api/internal/shared/eventbus/kafka_bus.go",
    "repository persists schema version": ROOT / "services/api/internal/modules/corpus/infrastructure/postgres/booking_repository.go",
    "dispatcher publishes event identity/version": ROOT / "services/api/internal/modules/corpus/infrastructure/postgres/outbox_dispatcher.go",
    "application declares event versions": ROOT / "services/api/internal/modules/corpus/application/commands/create_booking.go",
}
for label, path in checks.items():
    if not path.is_file():
        raise SystemExit(f"FAIL: missing {label}: {path}")

migration = checks["version migration"].read_text()
if "ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1" not in migration:
    raise SystemExit("FAIL: migration must add a backward-compatible schema_version default")
if "CHECK (schema_version > 0)" not in migration:
    raise SystemExit("FAIL: schema_version must be positive")

bus = checks["event bus version fields"].read_text()
if 'json:"event_id,omitempty"' not in bus or 'json:"schema_version,omitempty"' not in bus:
    raise SystemExit("FAIL: shared event envelope must expose optional event ID and schema version")

repository = checks["repository persists schema version"].read_text()
if "event_timestamp, schema_version, status" not in repository or "normalizedSchemaVersion(ev.SchemaVersion)" not in repository:
    raise SystemExit("FAIL: repository must persist a normalized schema version")

dispatcher = checks["dispatcher publishes event identity/version"].read_text()
if "o.schema_version" not in dispatcher or "ID: r.ID.String(), SchemaVersion: r.SchemaVersion" not in dispatcher:
    raise SystemExit("FAIL: dispatcher must publish outbox identity and schema version")

application = checks["application declares event versions"].read_text()
if application.count("SchemaVersion: 1") < 2:
    raise SystemExit("FAIL: booking-created and downstream handoff events must declare schema version 1")

print("Corpus event contract versioning static assertions passed")
