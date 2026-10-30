package application

import (
	"context"
	"testing"

	"github.com/google/uuid"
)

type orderWriterStub struct {
	calls  int
	cmd    CreateOrderCommand
	result Order
}

func (w *orderWriterStub) CreateOrder(_ context.Context, cmd CreateOrderCommand) (Order, error) {
	w.calls++
	w.cmd = cmd
	return w.result, nil
}

func TestOrderServiceDelegatesValidCommand(t *testing.T) {
	writer := &orderWriterStub{result: Order{ID: uuid.New()}}
	service := NewOrderService(writer)
	userID, restaurantID, itemID := uuid.New(), uuid.New(), uuid.New()
	got, err := service.Create(context.Background(), CreateOrderCommand{
		UserID: userID, RestaurantID: restaurantID, DeliveryAddress: "Main Street",
		Items: map[uuid.UUID]OrderItemCommand{itemID: {Quantity: 2, Notes: "no onions"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != writer.result.ID || writer.calls != 1 || writer.cmd.UserID != userID || writer.cmd.Items[itemID].Quantity != 2 {
		t.Fatalf("unexpected order delegation: got=%+v calls=%d command=%+v", got, writer.calls, writer.cmd)
	}
}

func TestOrderServiceRejectsInvalidItemsBeforePersistence(t *testing.T) {
	writer := &orderWriterStub{}
	service := NewOrderService(writer)
	itemID := uuid.New()
	_, err := service.Create(context.Background(), CreateOrderCommand{Items: map[uuid.UUID]OrderItemCommand{itemID: {Quantity: 0}}})
	if err == nil {
		t.Fatal("expected invalid item error")
	}
	if writer.calls != 0 {
		t.Fatalf("persistence called %d times for invalid item", writer.calls)
	}
}
