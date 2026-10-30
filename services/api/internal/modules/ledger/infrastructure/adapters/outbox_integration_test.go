package adapters

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"nidaw-backend/internal/modules/ledger/application/commands"
	"nidaw-backend/internal/modules/ledger/application/services"
	"nidaw-backend/internal/shared/eventbus"
)

// These tests require migrations including 018_ledger_event_outbox.sql to be
// applied to a dedicated PostgreSQL test database. They intentionally skip
// without NIDUS_TEST_DATABASE_URL; mocks alone cannot validate transaction
// atomicity or concurrent row claiming.
func openOutboxIntegrationPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("NIDUS_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("NIDUS_TEST_DATABASE_URL is not set; live PostgreSQL outbox integration tests skipped")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("create PostgreSQL pool: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Fatalf("ping PostgreSQL: %v", err)
	}
	var exists bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('public.ledger_event_outbox') IS NOT NULL`).Scan(&exists); err != nil || !exists {
		pool.Close()
		t.Fatalf("ledger_event_outbox missing; apply migration 018 first (exists=%v err=%v)", exists, err)
	}
	t.Cleanup(pool.Close)
	return pool
}

type pgxDBTx struct{ tx pgx.Tx }
type pgxRow struct{ row pgx.Row }

func (r pgxRow) Scan(dest ...interface{}) error { return r.row.Scan(dest...) }
func (t pgxDBTx) Exec(ctx context.Context, q string, args ...interface{}) (int64, error) {
	tag, err := t.tx.Exec(ctx, q, args...)
	return tag.RowsAffected(), err
}
func (t pgxDBTx) QueryRow(ctx context.Context, q string, args ...interface{}) services.Row {
	return pgxRow{row: t.tx.QueryRow(ctx, q, args...)}
}

var _ services.DBTx = pgxDBTx{}

type recordingOutboxBus struct {
	mu        sync.Mutex
	seen      map[string]int
	failFirst bool
	failed    map[string]bool
}

func newRecordingOutboxBus(failFirst bool) *recordingOutboxBus {
	return &recordingOutboxBus{seen: map[string]int{}, failed: map[string]bool{}, failFirst: failFirst}
}
func (b *recordingOutboxBus) Publish(_ context.Context, _ string, ev eventbus.Event) error {
	id, _ := ev.Payload["test_event_id"].(string)
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.failFirst && !b.failed[id] {
		b.failed[id] = true
		return errors.New("simulated broker outage")
	}
	b.seen[id]++
	return nil
}
func (b *recordingOutboxBus) Subscribe(context.Context, string, func(eventbus.Event)) error {
	return nil
}
func (b *recordingOutboxBus) Close() error { return nil }

func TestIntegration_OutboxRecordSharesTransactionAndDispatchesConcurrently(t *testing.T) {
	pool := openOutboxIntegrationPool(t)
	ctx := context.Background()
	publisher := NewEventBusPublisher(nil)

	// A rolled-back domain transaction must roll back its event record too.
	rollbackID := uuid.New().String()
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := publisher.Publish(ctx, pgxDBTx{tx: tx}, commands.Event{Type: "test.rollback", Topic: "nidaw.test", Timestamp: time.Now().Unix(), Payload: map[string]interface{}{"test_event_id": rollbackID}}); err != nil {
		_ = tx.Rollback(ctx)
		t.Fatal(err)
	}
	if err := tx.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	var rolledBackCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM ledger_event_outbox WHERE payload->>'test_event_id'=$1`, rollbackID).Scan(&rolledBackCount); err != nil {
		t.Fatal(err)
	}
	if rolledBackCount != 0 {
		t.Fatalf("outbox event survived transaction rollback: count=%d", rolledBackCount)
	}

	// Seed uniquely identifiable events and let independent dispatchers compete.
	const eventCount = 12
	ids := make([]string, 0, eventCount)
	for i := 0; i < eventCount; i++ {
		id := uuid.New().String()
		ids = append(ids, id)
		payload, _ := json.Marshal(map[string]interface{}{"test_event_id": id})
		if _, err := pool.Exec(ctx, `INSERT INTO ledger_event_outbox (id,event_type,topic,payload,event_timestamp,status,available_at) VALUES ($1,'test.concurrent','nidaw.test',$2::jsonb,$3,'pending',now())`, uuid.New(), string(payload), time.Now().Unix()); err != nil {
			t.Fatal(err)
		}
	}
	bus := newRecordingOutboxBus(false)
	const workers = 3
	var wg sync.WaitGroup
	errs := make(chan error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			d := NewOutboxDispatcher(pool, bus, time.Millisecond, zap.NewNop())
			if err := d.DispatchBatch(ctx); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Errorf("dispatcher: %v", err)
	}
	for _, id := range ids {
		var status string
		if err := pool.QueryRow(ctx, `SELECT status FROM ledger_event_outbox WHERE payload->>'test_event_id'=$1`, id).Scan(&status); err != nil {
			t.Fatal(err)
		}
		if status != "published" {
			t.Errorf("event %s status=%s, want published", id, status)
		}
		bus.mu.Lock()
		count := bus.seen[id]
		bus.mu.Unlock()
		if count != 1 {
			t.Errorf("event %s delivered %d times during concurrent dispatch, want 1", id, count)
		}
	}
	// Clean up only rows created by this test.
	if _, err := pool.Exec(ctx, `DELETE FROM ledger_event_outbox WHERE payload->>'test_event_id'=ANY($1)`, ids); err != nil {
		t.Errorf("cleanup test rows: %v", err)
	}
}

func TestIntegration_OutboxRetriesAfterBrokerFailure(t *testing.T) {
	pool := openOutboxIntegrationPool(t)
	ctx := context.Background()
	id := uuid.New().String()
	payload, _ := json.Marshal(map[string]interface{}{"test_event_id": id})
	_, err := pool.Exec(ctx, `INSERT INTO ledger_event_outbox (id,event_type,topic,payload,event_timestamp,status,available_at) VALUES ($1,'test.retry','nidaw.test',$2::jsonb,$3,'pending',now())`, uuid.New(), string(payload), time.Now().Unix())
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM ledger_event_outbox WHERE payload->>'test_event_id'=$1`, id)
	bus := newRecordingOutboxBus(true)
	d := NewOutboxDispatcher(pool, bus, time.Millisecond, zap.NewNop())
	if err := d.DispatchBatch(ctx); err != nil {
		t.Fatal(err)
	}
	var status string
	var attempts int
	if err := pool.QueryRow(ctx, `SELECT status, attempts FROM ledger_event_outbox WHERE payload->>'test_event_id'=$1`, id).Scan(&status, &attempts); err != nil {
		t.Fatal(err)
	}
	if status != "pending" || attempts != 1 {
		t.Fatalf("after broker failure status=%s attempts=%d; want pending/1", status, attempts)
	}
	// Make the retry immediately eligible rather than sleeping through backoff.
	if _, err := pool.Exec(ctx, `UPDATE ledger_event_outbox SET available_at=now() WHERE payload->>'test_event_id'=$1`, id); err != nil {
		t.Fatal(err)
	}
	if err := d.DispatchBatch(ctx); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `SELECT status FROM ledger_event_outbox WHERE payload->>'test_event_id'=$1`, id).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "published" {
		t.Fatalf("after successful retry status=%s, want published", status)
	}
}
