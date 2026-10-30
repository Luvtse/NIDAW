-- Destructive rollback: pending and published Logix events are discarded.
DROP INDEX IF EXISTS idx_logix_event_outbox_pending;
DROP TABLE IF EXISTS logix_event_outbox;
