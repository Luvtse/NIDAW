#!/usr/bin/env python3
"""Static regression checks for Corpus approval lifecycle boundaries."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
repo = ROOT / "services/api/internal/modules/corpus"
ports = (repo / "application/ports/booking_repository.go").read_text()
command = (repo / "application/commands/decide_booking.go").read_text()
repository = (repo / "infrastructure/postgres/booking_repository.go").read_text()
router = (repo / "interfaces/http/router.go").read_text()
migration = (ROOT / "data/migrations/postgres/023_corpus_approval_decisions.sql").read_text()

checks = {
    "application decision delegates through repository port": "DecideBooking(ctx context.Context, bookingID, approverUserID uuid.UUID, approve bool, notes string) error" in ports,
    "approval command rejects missing authenticated identity": "approverUserID == uuid.Nil" in command,
    "approval command bounds notes": "len(notes) > 2000" in command,
    "repository locks booking before transition": "FOR UPDATE OF b" in repository,
    "repository checks assigned authenticated approver": "e.user_id = $2" in repository and "e.status = 'active'" in repository,
    "repository only transitions pending bookings": "status != \"pending_approval\"" in repository and "WHERE id = $1 AND status = 'pending_approval'" in repository,
    "decision and outbox event share transaction": "return r.db.WithTx(ctx, func(tx *database.Tx) error" in repository and "persist Corpus booking decision event" in repository,
    "approve/reject routes are registered": '"/bookings/{bookingID}/approve"' in router and '"/bookings/{bookingID}/reject"' in router,
    "approval decision metadata migration exists": "approval_decided_at" in migration and "approval_notes" in migration,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(1)
