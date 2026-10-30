-- Corpus outbound events are committed atomically with corporate bookings.
-- Delivery is at-least-once; downstream consumers must be idempotent.
CREATE TABLE IF NOT EXISTS corpus_event_outbox (
    id uuid PRIMARY KEY,
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
CREATE INDEX IF NOT EXISTS idx_corpus_event_outbox_pending
    ON corpus_event_outbox (available_at, created_at)
    WHERE status IN ('pending', 'processing');
