#!/usr/bin/env python3
"""Static regression checks for Logix transactional customs event delivery."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
repo = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/customs_repository.go").read_text()
dispatcher = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/outbox_dispatcher.go").read_text()
service = (ROOT / "services/api/internal/modules/logix/application/services/customs_service.go").read_text()
main = (ROOT / "services/api/cmd/server/main.go").read_text()
migration = (ROOT / "data/migrations/postgres/024_logix_event_outbox.sql").read_text()
checks = {
    "submission event inserted inside repository transaction": 'insertOutboxEvent(ctx, tx, "logix.customs.submitted"' in repo,
    "clearance event inserted inside repository transaction": 'insertOutboxEvent(ctx, tx, "logix.customs.cleared"' in repo,
    "submission transition rejects already-submitted rows": "status = 'prepared'" in repo,
    "outbox event payload is JSON encoded": "json.Marshal(payload)" in repo,
    "dispatcher claims work with SKIP LOCKED": "FOR UPDATE SKIP LOCKED" in dispatcher,
    "dispatcher reclaims stale processing leases": "locked_at < now() - interval '1 minute'" in dispatcher,
    "dispatcher retries failed publications": "available_at=now() + LEAST" in dispatcher,
    "dispatcher publishes event identity and schema version": "ID: record.ID.String(), SchemaVersion: record.SchemaVersion" in dispatcher,
    "application service does not publish after commit": "s.bus.Publish" not in service,
    "runtime composition checks complete schema before starting dispatcher": "CheckOutboxSchema(ctxLogixSchema, db.Pool())" in main and "NewOutboxDispatcher(db.Pool(), eventBus" in main,
    "schema preflight rejects missing outbox table and columns": "Logix outbox schema is incomplete" in dispatcher and "information_schema.columns" in dispatcher,
    "migration defines versioned event outbox": "schema_version integer NOT NULL DEFAULT 1" in migration,
    "migration indexes pending/processing events": "idx_logix_event_outbox_pending" in migration,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"{len(checks) - len(failed)}/{len(checks)} Logix transactional outbox assertions passed")
raise SystemExit(1 if failed else 0)
