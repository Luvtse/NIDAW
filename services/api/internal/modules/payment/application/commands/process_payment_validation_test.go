package commands

import (
	"errors"
	"strings"
	"testing"

	"nidaw-backend/internal/modules/payment/domain/entities"

	"github.com/google/uuid"
)

func validProcessPaymentCommand() *ProcessPaymentCommand {
	return &ProcessPaymentCommand{
		UserID:          uuid.New(),
		OrderID:         uuid.New(),
		OrderType:       entities.OrderTypeRide,
		Amount:          125.50,
		Currency:        "ETB",
		PaymentMethodID: "telebirr",
		IdempotencyKey:  "charge-123",
	}
}

func TestValidateCommandRequiresBoundedIdempotencyKey(t *testing.T) {
	h := NewProcessPaymentHandler(nil, nil, nil, nil)

	for _, key := range []string{"", "   ", strings.Repeat("x", 256)} {
		cmd := validProcessPaymentCommand()
		cmd.IdempotencyKey = key
		if err := h.validateCommand(cmd); !errors.Is(err, ErrIdempotencyKeyRequired) {
			t.Errorf("key length %d: got error %v, want ErrIdempotencyKeyRequired", len(key), err)
		}
	}
}

func TestSamePaymentRequestRequiresSameFinancialIntent(t *testing.T) {
	cmd := validProcessPaymentCommand()
	existing := &entities.Transaction{
		UserID:        cmd.UserID,
		OrderID:       cmd.OrderID,
		OrderType:     cmd.OrderType,
		Amount:        cmd.Amount,
		Currency:      cmd.Currency,
		PaymentMethod: determinePaymentMethod(cmd.PaymentMethodID),
	}

	if !samePaymentRequest(existing, cmd) {
		t.Fatal("identical request should be accepted as an idempotent replay")
	}

	mutations := []struct {
		name   string
		mutate func(*ProcessPaymentCommand)
	}{
		{"amount", func(c *ProcessPaymentCommand) { c.Amount++ }},
		{"order", func(c *ProcessPaymentCommand) { c.OrderID = uuid.New() }},
		{"user", func(c *ProcessPaymentCommand) { c.UserID = uuid.New() }},
		{"order type", func(c *ProcessPaymentCommand) { c.OrderType = entities.OrderTypeFood }},
		{"currency", func(c *ProcessPaymentCommand) { c.Currency = "USD" }},
		{"payment method", func(c *ProcessPaymentCommand) { c.PaymentMethodID = "bank_transfer" }},
	}
	for _, tc := range mutations {
		t.Run(tc.name, func(t *testing.T) {
			changed := *cmd
			tc.mutate(&changed)
			if samePaymentRequest(existing, &changed) {
				t.Fatal("different financial intent must not replay under the same idempotency key")
			}
		})
	}
}

func TestMetadataCopyDoesNotMutateCallerMap(t *testing.T) {
	metadata := map[string]string{"source": "mobile"}
	copied := paymentMetadata(metadata, "charge-123")
	if copied["idempotency_key"] != "charge-123" {
		t.Fatal("copy must include the normalized idempotency key")
	}
	if _, ok := metadata["idempotency_key"]; ok {
		t.Fatal("adding the idempotency key must not mutate caller-owned metadata")
	}
	if copied["source"] != metadata["source"] {
		t.Fatal("copy must preserve existing metadata")
	}
}
