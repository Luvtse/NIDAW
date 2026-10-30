package application

import (
	"context"
	"testing"

	"github.com/google/uuid"
)

type hotelReaderStub struct {
	filter HotelFilter
	id     uuid.UUID
	list   []Hotel
	one    Hotel
}

func (r *hotelReaderStub) ListHotels(_ context.Context, filter HotelFilter) ([]Hotel, error) {
	r.filter = filter
	return r.list, nil
}

func (r *hotelReaderStub) GetHotel(_ context.Context, id uuid.UUID) (Hotel, error) {
	r.id = id
	return r.one, nil
}

func TestCatalogServiceBoundsListLimitAndDelegatesFilter(t *testing.T) {
	reader := &hotelReaderStub{list: []Hotel{{ID: uuid.New()}}}
	service := NewCatalogService(reader)
	items, err := service.ListHotels(context.Background(), HotelFilter{City: "Addis", CountryCode: "ET", Limit: 1000})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || reader.filter.Limit != 100 || reader.filter.City != "Addis" || reader.filter.CountryCode != "ET" {
		t.Fatalf("unexpected catalog delegation: items=%d filter=%+v", len(items), reader.filter)
	}
}

func TestCatalogServiceUsesDefaultLimit(t *testing.T) {
	reader := &hotelReaderStub{}
	service := NewCatalogService(reader)
	if _, err := service.ListHotels(context.Background(), HotelFilter{}); err != nil {
		t.Fatal(err)
	}
	if reader.filter.Limit != 20 {
		t.Fatalf("expected default limit 20, got %d", reader.filter.Limit)
	}
}

func TestCatalogServiceDelegatesHotelDetail(t *testing.T) {
	reader := &hotelReaderStub{one: Hotel{ID: uuid.New()}}
	service := NewCatalogService(reader)
	id := uuid.New()
	got, err := service.GetHotel(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	if reader.id != id || got.ID != reader.one.ID {
		t.Fatalf("unexpected hotel detail delegation: requested=%s got=%s", reader.id, got.ID)
	}
}
