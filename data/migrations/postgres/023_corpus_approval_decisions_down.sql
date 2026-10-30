-- Destructive rollback: removes approval decision metadata.
DROP INDEX IF EXISTS idx_corporate_bookings_pending_approver;
ALTER TABLE corporate_bookings
    DROP COLUMN IF EXISTS approval_notes,
    DROP COLUMN IF EXISTS approval_decided_at;
