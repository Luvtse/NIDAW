package postgres

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

// OutboxDispatcher publishes committed Corpus events at least once. Consumers
// must be idempotent because a crash after broker acceptance can cause replay.
type OutboxDispatcher struct {
	pool      *pgxpool.Pool
	bus       eventbus.EventBus
	logger    *zap.Logger
	interval  time.Duration
	batchSize int
}

type outboxRecord struct {
	ID            uuid.UUID
	SchemaVersion int
	Type          string
	Topic         string
	Payload       map[string]interface{}
	Timestamp     int64
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
				d.logger.Error("corpus outbox dispatch failed", zap.Error(err))
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *OutboxDispatcher) DispatchBatch(ctx context.Context) error {
	if d == nil || d.pool == nil || d.bus == nil {
		return nil
	}
	for i := 0; i < d.batchSize; i++ {
		var r outboxRecord
		err := d.pool.QueryRow(ctx, `WITH candidate AS (
			SELECT id FROM corpus_event_outbox
			WHERE (status = 'pending' AND available_at <= now())
			   OR (status = 'processing' AND locked_at < now() - interval '1 minute')
			ORDER BY created_at, id FOR UPDATE SKIP LOCKED LIMIT 1
		) UPDATE corpus_event_outbox o SET status='processing', locked_at=now(), attempts=attempts+1
		  FROM candidate c WHERE o.id=c.id
		  RETURNING o.id, o.schema_version, o.event_type, o.topic, o.payload, o.event_timestamp`).Scan(&r.ID, &r.SchemaVersion, &r.Type, &r.Topic, &r.Payload, &r.Timestamp)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("claim Corpus outbox row: %w", err)
		}
		if err = d.bus.Publish(ctx, r.Topic, eventbus.Event{ID: r.ID.String(), SchemaVersion: r.SchemaVersion, Type: r.Type, Payload: r.Payload, Timestamp: r.Timestamp}); err != nil {
			_, updateErr := d.pool.Exec(ctx, `UPDATE corpus_event_outbox SET status='pending', locked_at=NULL,
				last_error=left($2, 2000), available_at=now() + LEAST(interval '5 minutes', interval '1 second' * power(2, LEAST(attempts, 8)))
				WHERE id=$1`, r.ID, err.Error())
			if updateErr != nil {
				return fmt.Errorf("publish Corpus event: %v; release outbox row: %w", err, updateErr)
			}
			d.logger.Warn("Corpus event publish failed; scheduled retry", zap.String("event_id", r.ID.String()), zap.Error(err))
			continue
		}
		if _, err := d.pool.Exec(ctx, `UPDATE corpus_event_outbox SET status='published', published_at=now(), locked_at=NULL, last_error=NULL WHERE id=$1`, r.ID); err != nil {
			return fmt.Errorf("mark Corpus event published (event may be redelivered): %w", err)
		}
	}
	return nil
}
