-- Logix domain events are committed atomically with customs state transitions.
-- Delivery is at-least-once; downstream consumers must deduplicate by event_id.
CREATE TABLE IF NOT EXISTS logix_event_outbox (
    id uuid PRIMARY KEY,
    schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    event_type text NOT NULL,
    topic text NOT NULL,
    payload jsonb NOT NULL,
    event_timestamp bigint NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'published')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at timestamptz NOT NULL DEFAULT now(),
    locked_at timestamptz,
    last_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_logix_event_outbox_pending
    ON logix_event_outbox (available_at, created_at)
    WHERE status IN ('pending', 'processing');
