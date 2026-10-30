-- Record explicit corporate booking approval decisions.
ALTER TABLE corporate_bookings
    ADD COLUMN IF NOT EXISTS approval_decided_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS approval_notes TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_corporate_bookings_pending_approver
    ON corporate_bookings (approver_id, created_at)
    WHERE status = 'pending_approval';
