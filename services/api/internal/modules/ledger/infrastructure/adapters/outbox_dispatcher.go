package adapters

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"nidaw-backend/internal/shared/eventbus"
)

// OutboxDispatcher delivers committed ledger events to the event bus. Delivery
// is at-least-once: a process crash after Kafka accepts an event but before the
// row is marked published can produce a duplicate, so consumers must be idempotent.
type OutboxDispatcher struct {
	pool      *pgxpool.Pool
	bus       eventbus.EventBus
	logger    *zap.Logger
	interval  time.Duration
	batchSize int
}

type outboxRecord struct {
	ID        uuid.UUID
	Type      string
	Topic     string
	Payload   map[string]interface{}
	Timestamp int64
}

func NewOutboxDispatcher(pool *pgxpool.Pool, bus eventbus.EventBus, interval time.Duration, logger *zap.Logger) *OutboxDispatcher {
	if interval <= 0 {
		interval = time.Second
	}
	if logger == nil {
		logger = zap.NewNop()
	}
	return &OutboxDispatcher{pool: pool, bus: bus, logger: logger, interval: interval, batchSize: 50}
}

func (d *OutboxDispatcher) Run(ctx context.Context) {
	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()
	for {
		if d.pool != nil && d.bus != nil {
			if err := d.DispatchBatch(ctx); err != nil && !errors.Is(err, context.Canceled) {
				d.logger.Error("ledger outbox dispatch failed", zap.Error(err))
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// DispatchBatch claims one row at a time using SKIP LOCKED, then publishes it.
// Expired processing leases are eligible again after one minute.
func (d *OutboxDispatcher) DispatchBatch(ctx context.Context) error {
	if d.pool == nil || d.bus == nil {
		return nil
	}
	for i := 0; i < d.batchSize; i++ {
		var r outboxRecord
		err := d.pool.QueryRow(ctx, `WITH candidate AS (
    SELECT id FROM ledger_event_outbox
    WHERE (status = 'pending' AND available_at <= now())
       OR (status = 'processing' AND locked_at < now() - interval '1 minute')
    ORDER BY created_at, id FOR UPDATE SKIP LOCKED LIMIT 1
   ) UPDATE ledger_event_outbox o SET status='processing', locked_at=now(), attempts=attempts+1
     FROM candidate c WHERE o.id=c.id
   RETURNING o.id, o.event_type, o.topic, o.payload, o.event_timestamp`).Scan(&r.ID, &r.Type, &r.Topic, &r.Payload, &r.Timestamp)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("claim ledger outbox row: %w", err)
		}
		publishErr := d.bus.Publish(ctx, r.Topic, eventbus.Event{Type: r.Type, Payload: r.Payload, Timestamp: r.Timestamp})
		if publishErr != nil {
			_, updateErr := d.pool.Exec(ctx, `UPDATE ledger_event_outbox SET status='pending', locked_at=NULL,
      last_error=left($2, 2000), available_at=now() + LEAST(interval '5 minutes', interval '1 second' * power(2, LEAST(attempts, 8)))
      WHERE id=$1`, r.ID, publishErr.Error())
			if updateErr != nil {
				return fmt.Errorf("publish ledger event: %v; release outbox row: %w", publishErr, updateErr)
			}
			d.logger.Warn("ledger event publish failed; scheduled retry", zap.String("event_id", r.ID.String()), zap.Error(publishErr))
			continue
		}
		if _, err := d.pool.Exec(ctx, `UPDATE ledger_event_outbox SET status='published', published_at=now(), locked_at=NULL, last_error=NULL WHERE id=$1`, r.ID); err != nil {
			return fmt.Errorf("mark ledger event published (event may be redelivered): %w", err)
		}
	}
	return nil
}
