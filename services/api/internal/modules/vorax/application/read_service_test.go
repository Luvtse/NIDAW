package application

import (
	"context"
	"testing"

	"github.com/google/uuid"
)

type restaurantReaderStub struct{ gotLimit int }

func (s *restaurantReaderStub) ListRestaurants(_ context.Context, _, _ string, limit int) ([]Restaurant, error) {
	s.gotLimit = limit
	return []Restaurant{}, nil
}
func (*restaurantReaderStub) GetRestaurant(context.Context, uuid.UUID) (Restaurant, error) {
	return Restaurant{}, nil
}
func (*restaurantReaderStub) ListMenu(context.Context, uuid.UUID) ([]MenuItem, error) {
	return []MenuItem{}, nil
}

type orderReaderStub struct{ gotLimit int }

func (s *orderReaderStub) ListOrders(_ context.Context, _ uuid.UUID, limit int) ([]OrderSummary, error) {
	s.gotLimit = limit
	return []OrderSummary{}, nil
}
func (*orderReaderStub) TrackOrder(context.Context, uuid.UUID, uuid.UUID) (OrderTracking, error) {
	return OrderTracking{}, nil
}
func TestReadServiceBoundsRestaurantLimit(t *testing.T) {
	reader := &restaurantReaderStub{}
	service := NewReadService(reader, &orderReaderStub{})
	if _, err := service.ListRestaurants(context.Background(), "", "", 500); err != nil {
		t.Fatal(err)
	}
	if reader.gotLimit != 100 {
		t.Fatalf("limit=%d, want 100", reader.gotLimit)
	}
}
func TestReadServiceBoundsOrderLimit(t *testing.T) {
	reader := &orderReaderStub{}
	service := NewReadService(&restaurantReaderStub{}, reader)
	if _, err := service.ListOrders(context.Background(), uuid.New(), -1); err != nil {
		t.Fatal(err)
	}
	if reader.gotLimit != 20 {
		t.Fatalf("limit=%d, want default 20", reader.gotLimit)
	}
}
