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

// OutboxDispatcher publishes committed Logix events at least once. Consumers
// must deduplicate by event ID because a crash after broker acceptance can replay.
type OutboxDispatcher struct {
	pool      *pgxpool.Pool
	bus       eventbus.EventBus
	logger    *zap.Logger
	interval  time.Duration
	batchSize int
}

type logixOutboxRecord struct {
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

// CheckOutboxSchema verifies the full schema contract required by the dispatcher.
// A table-exists check alone is insufficient: a partially applied or incompatible
// migration would otherwise start a worker that fails continuously at runtime.
func CheckOutboxSchema(ctx context.Context, pool *pgxpool.Pool) error {
	if pool == nil {
		return errors.New("Logix outbox database pool is not configured")
	}
	var exists bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('public.logix_event_outbox') IS NOT NULL`).Scan(&exists); err != nil {
		return fmt.Errorf("check Logix outbox table: %w", err)
	}
	if !exists {
		return errors.New("Logix outbox table is missing; apply migration 024_logix_event_outbox.sql")
	}
	rows, err := pool.Query(ctx, `SELECT column_name FROM information_schema.columns
		WHERE table_schema = 'public' AND table_name = 'logix_event_outbox'`)
	if err != nil {
		return fmt.Errorf("inspect Logix outbox columns: %w", err)
	}
	defer rows.Close()
	columns := make(map[string]bool)
	for rows.Next() {
		var column string
		if err := rows.Scan(&column); err != nil {
			return fmt.Errorf("scan Logix outbox column: %w", err)
		}
		columns[column] = true
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("read Logix outbox columns: %w", err)
	}
	required := []string{"id", "schema_version", "event_type", "topic", "payload", "event_timestamp", "status", "attempts", "available_at", "locked_at", "last_error", "created_at", "published_at"}
	missing := make([]string, 0)
	for _, column := range required {
		if !columns[column] {
			missing = append(missing, column)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("Logix outbox schema is incomplete; missing columns: %v", missing)
	}
	return nil
}

func (d *OutboxDispatcher) Run(ctx context.Context) {
	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()
	for {
		if d.pool != nil && d.bus != nil {
			if err := d.DispatchBatch(ctx); err != nil && !errors.Is(err, context.Canceled) {
				d.logger.Error("Logix outbox dispatch failed", zap.Error(err))
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
		var record logixOutboxRecord
		err := d.pool.QueryRow(ctx, `WITH candidate AS (
			SELECT id FROM logix_event_outbox
			WHERE (status = 'pending' AND available_at <= now())
			   OR (status = 'processing' AND locked_at < now() - interval '1 minute')
			ORDER BY created_at, id FOR UPDATE SKIP LOCKED LIMIT 1
		) UPDATE logix_event_outbox o SET status='processing', locked_at=now(), attempts=attempts+1
		  FROM candidate c WHERE o.id=c.id
		  RETURNING o.id, o.schema_version, o.event_type, o.topic, o.payload, o.event_timestamp`).
			Scan(&record.ID, &record.SchemaVersion, &record.Type, &record.Topic, &record.Payload, &record.Timestamp)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("claim Logix outbox row: %w", err)
		}
		if err = d.bus.Publish(ctx, record.Topic, eventbus.Event{
			ID: record.ID.String(), SchemaVersion: record.SchemaVersion,
			Type: record.Type, Payload: record.Payload, Timestamp: record.Timestamp,
		}); err != nil {
			_, updateErr := d.pool.Exec(ctx, `UPDATE logix_event_outbox SET status='pending', locked_at=NULL,
				last_error=left($2, 2000), available_at=now() + LEAST(interval '5 minutes', interval '1 second' * power(2, LEAST(attempts, 8)))
				WHERE id=$1`, record.ID, err.Error())
			if updateErr != nil {
				return fmt.Errorf("publish Logix event: %v; release outbox row: %w", err, updateErr)
			}
			d.logger.Warn("Logix event publish failed; scheduled retry", zap.String("event_id", record.ID.String()), zap.Error(err))
			continue
		}
		if _, err := d.pool.Exec(ctx, `UPDATE logix_event_outbox SET status='published', published_at=now(), locked_at=NULL, last_error=NULL WHERE id=$1`, record.ID); err != nil {
			return fmt.Errorf("mark Logix event published (event may be redelivered): %w", err)
		}
	}
	return nil
}
