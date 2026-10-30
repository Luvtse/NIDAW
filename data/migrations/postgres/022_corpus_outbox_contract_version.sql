-- Add explicit event contract versioning without changing existing event payloads.
-- Existing rows are version 1; consumers can branch on schema_version.
ALTER TABLE corpus_event_outbox
    ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1
    CHECK (schema_version > 0);
