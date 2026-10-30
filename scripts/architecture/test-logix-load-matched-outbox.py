#!/usr/bin/env python3
"""Static regression checks for the versioned Logix load-match event path."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
matcher = (ROOT / "services/api/internal/modules/logix/application/services/load_matcher.go").read_text()
repo = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/load_match_event_repository.go").read_text()
carrier_repo = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/carrier_repository.go").read_text()
customs_repo = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/customs_repository.go").read_text()
catalog = json.loads((ROOT / "packages/event-contracts/catalog.json").read_text())
event = next(item for item in catalog["events"] if item["type"] == "logix.load.matched")
dispatcher = (ROOT / "services/api/internal/modules/logix/infrastructure/postgres/outbox_dispatcher.go").read_text()
main = (ROOT / "services/api/cmd/server/main.go").read_text()
checks = {
    "Logix outbox startup verifies full schema contract": "CheckOutboxSchema(ctxLogixSchema, db.Pool())" in main and "Logix outbox schema is incomplete" in dispatcher,
    "matcher uses application event writer port": "type LoadMatchEventWriter interface" in matcher and "eventWriter LoadMatchEventWriter" in matcher,
    "matcher depends on carrier repository port": "type CarrierRepository interface" in matcher and "carriers CarrierRepository" in matcher,
    "equal scores have deterministic carrier-ID tie-break": "scores[i].CarrierID.String() < scores[j].CarrierID.String()" in matcher,
    "carrier SQL lives in PostgreSQL adapter": "FROM carriers" not in matcher and "FROM carriers" in carrier_repo and "var _ services.CarrierRepository" in carrier_repo,
    "carrier adapter checks row iteration errors": "rows.Err()" in carrier_repo,
    "matcher no longer imports shared database": '"nidaw-backend/internal/shared/database"' not in matcher,
    "matcher no longer imports eventbus": '"nidaw-backend/internal/shared/eventbus"' not in matcher,
    "matcher no longer publishes directly": "m.bus.Publish" not in matcher and "m.eventWriter.RecordLoadMatched" in matcher,
    "event write failure propagates": 'return nil, fmt.Errorf("record load-matched event: %w", err)' in matcher,
    "nil load rejected": 'load == nil || load.ID == uuid.Nil' in matcher,
    "writer validates identifiers": "load.ID == uuid.Nil || carrierID == uuid.Nil" in repo,
    "writer rejects invalid score and rate": "math.IsNaN(score)" in repo and "math.IsInf(load.Rate, 0)" in repo,
    "writer writes version 1 to outbox": "VALUES ($1, 1, 'logix.load.matched', 'logix.loads'" in repo,
    "writer uses transaction boundary": "r.db.WithTx(ctx" in repo and "tx.Exec(ctx" in repo,
    "writer shares Logix outbox contract": "logix_event_outbox" in repo and "event_id" in repo,
    "outbox migration exists": (ROOT / "data/migrations/postgres/024_logix_event_outbox.sql").is_file(),
    "catalogue marks event as v1": event["schema_version"] == 1,
    "catalogue lists writer source": "services/api/internal/modules/logix/infrastructure/postgres/load_match_event_repository.go" in event["source_paths"],
    "catalogue discloses consumer gap": "no active downstream consumer identified" in event["consumer_status"].lower(),
    "customs events use same versioned outbox helper": "VALUES ($1, 1, $2, $3, $4::jsonb, $5)" in customs_repo,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
print(f"{len(checks) - len(failed)}/{len(checks)} checks passed")
if failed:
    raise SystemExit(1)
