package adapters

import (
	"context"
	"strings"
	"testing"

	"nidaw-backend/internal/modules/ledger/application/commands"
	"nidaw-backend/internal/modules/ledger/application/services"
)

type captureTx struct {
	query string
	args  []interface{}
	err   error
}

func (t *captureTx) Exec(_ context.Context, q string, args ...interface{}) (int64, error) {
	t.query = q
	t.args = args
	return 1, t.err
}
func (t *captureTx) QueryRow(context.Context, string, ...interface{}) services.Row { return nil }

func TestEventBusPublisherPersistsOutboxRecordInProvidedTransaction(t *testing.T) {
	tx := &captureTx{}
	publisher := NewEventBusPublisher(nil)
	err := publisher.Publish(context.Background(), tx, commands.Event{Type: "ledger.ride_settled", Topic: "nidaw.ledger", Timestamp: 123, Payload: map[string]interface{}{"ride_id": "ride-1"}})
	if err != nil {
		t.Fatalf("Publish returned error: %v", err)
	}
	if !strings.Contains(tx.query, "INSERT INTO ledger_event_outbox") {
		t.Fatalf("expected outbox insert, got %q", tx.query)
	}
	if len(tx.args) != 5 {
		t.Fatalf("expected 5 SQL args, got %d", len(tx.args))
	}
	if tx.args[1] != "ledger.ride_settled" || tx.args[2] != "nidaw.ledger" || tx.args[4] != int64(123) {
		t.Fatalf("unexpected event args: %#v", tx.args)
	}
}

func TestEventBusPublisherRequiresTransaction(t *testing.T) {
	if err := NewEventBusPublisher(nil).Publish(context.Background(), nil, commands.Event{Type: "example"}); err == nil {
		t.Fatal("expected error without transaction")
	}
}
