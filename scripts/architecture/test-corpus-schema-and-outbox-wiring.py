#!/usr/bin/env python3
"""Static regression checks for Corpus-owned schema and outbox startup wiring."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "data/migrations/postgres"
SCHEMA = (MIGRATIONS / "021_corpus_core_schema.sql").read_text()
OUTBOX = (MIGRATIONS / "020_corpus_event_outbox.sql").read_text()
REPOSITORY = (ROOT / "services/api/internal/modules/corpus/infrastructure/postgres/booking_repository.go").read_text()
DISPATCHER = (ROOT / "services/api/internal/modules/corpus/infrastructure/postgres/outbox_dispatcher.go").read_text()
SERVER = (ROOT / "services/api/cmd/server/main.go").read_text()

for table in ("corporate_accounts", "corporate_employees", "travel_policies", "corporate_bookings"):
    assert f"CREATE TABLE IF NOT EXISTS {table}" in SCHEMA, f"missing Corpus schema table: {table}"
for column in ("booking_data", "payment_method", "policy_compliant", "violations", "estimated_amount", "requires_approval", "approver_id"):
    assert column in SCHEMA, f"missing corporate_bookings column: {column}"
assert "REFERENCES users(id)" in SCHEMA
assert "INSERT INTO corporate_bookings" in REPOSITORY
assert "INSERT INTO corpus_event_outbox" in REPOSITORY
assert "r.db.WithTx(ctx" in REPOSITORY, "booking and outbox inserts must share one transaction"
assert "FOR UPDATE SKIP LOCKED" in DISPATCHER
assert "available_at=now() + LEAST" in DISPATCHER, "retry backoff is missing"
assert "to_regclass('public.corpus_event_outbox') IS NOT NULL" in SERVER
assert "Corpus transactional outbox dispatcher online" in SERVER
assert "CREATE TABLE IF NOT EXISTS corpus_event_outbox" in OUTBOX
print("Corpus schema and outbox wiring static assertions passed")
