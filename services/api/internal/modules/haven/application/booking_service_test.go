package application

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	havendomain "nidaw-backend/internal/modules/haven/domain"
)

type writerStub struct {
	calls          int
	cancelCalls    int
	inventoryCalls int
	cancelErr      error
	inventoryErr   error
}

func (w *writerStub) CreateBooking(_ context.Context, cmd CreateBookingCommand) (Booking, error) {
	w.calls++
	return Booking{UserID: cmd.UserID, HotelID: cmd.HotelID, CheckIn: cmd.CheckIn, CheckOut: cmd.CheckOut}, nil
}

func TestBookingServiceRejectsInvalidStayBeforePersistence(t *testing.T) {
	writer := &writerStub{}
	service := NewBookingService(writer)
	today := time.Date(2026, 10, 24, 0, 0, 0, 0, time.UTC)
	_, err := service.Create(context.Background(), CreateBookingCommand{
		UserID: uuid.New(), HotelID: uuid.New(), CheckIn: today.AddDate(0, 0, 2),
		CheckOut: today.AddDate(0, 0, 1), Guests: 2, Rooms: 1, Today: today,
	})
	if err == nil {
		t.Fatal("expected invalid stay error")
	}
	if writer.calls != 0 {
		t.Fatalf("persistence called %d times for invalid stay", writer.calls)
	}
}

func TestBookingServiceDelegatesValidStay(t *testing.T) {
	writer := &writerStub{}
	service := NewBookingService(writer)
	today := time.Date(2026, 10, 24, 0, 0, 0, 0, time.UTC)
	cmd := CreateBookingCommand{UserID: uuid.New(), HotelID: uuid.New(), CheckIn: today.AddDate(0, 0, 1), CheckOut: today.AddDate(0, 0, 2), Guests: 2, Rooms: 1, Today: today}
	if _, err := service.Create(context.Background(), cmd); err != nil {
		t.Fatal(err)
	}
	if writer.calls != 1 {
		t.Fatalf("expected one persistence call, got %d", writer.calls)
	}
}

func (w *writerStub) CancelBooking(_ context.Context, _, _ uuid.UUID) error {
	w.cancelCalls++
	return w.cancelErr
}

func (w *writerStub) SetInventory(_ context.Context, _ uuid.UUID, _ time.Time, rooms int) error {
	w.inventoryCalls++
	if rooms < 1 || rooms > 10000 {
		return havendomain.ErrInvalidOccupancy
	}
	return w.inventoryErr
}

func TestBookingServiceDelegatesCancellation(t *testing.T) {
	writer := &writerStub{}
	service := NewBookingService(writer)
	if err := service.Cancel(context.Background(), uuid.New(), uuid.New()); err != nil {
		t.Fatal(err)
	}
	if writer.cancelCalls != 1 {
		t.Fatalf("expected one cancellation call, got %d", writer.cancelCalls)
	}
}

func TestBookingServiceRejectsInvalidInventoryBeforePersistence(t *testing.T) {
	writer := &writerStub{}
	service := NewBookingService(writer)
	if err := service.ConfigureInventory(context.Background(), uuid.New(), time.Now(), 0); err == nil {
		t.Fatal("expected invalid inventory capacity error")
	}
	if writer.inventoryCalls != 0 {
		t.Fatalf("persistence called %d times for invalid inventory", writer.inventoryCalls)
	}
}

type readerStub struct {
	listedUser uuid.UUID
	listLimit  int
	gotUser    uuid.UUID
	gotBooking uuid.UUID
	listResult []Booking
	getResult  Booking
	getErr     error
}

func (r *readerStub) ListBookings(_ context.Context, userID uuid.UUID, limit int) ([]Booking, error) {
	r.listedUser, r.listLimit = userID, limit
	return r.listResult, nil
}

func (r *readerStub) GetBooking(_ context.Context, userID, bookingID uuid.UUID) (Booking, error) {
	r.gotUser, r.gotBooking = userID, bookingID
	return r.getResult, r.getErr
}

func TestBookingServiceDelegatesOwnedBookingReads(t *testing.T) {
	reader := &readerStub{listResult: []Booking{{ID: uuid.New()}}}
	service := NewBookingService(&writerStub{}, reader)
	userID, bookingID := uuid.New(), uuid.New()
	items, err := service.List(context.Background(), userID, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || reader.listedUser != userID || reader.listLimit != 100 {
		t.Fatalf("unexpected list delegation: items=%d user=%s limit=%d", len(items), reader.listedUser, reader.listLimit)
	}
	want := Booking{ID: bookingID, UserID: userID}
	reader.getResult = want
	got, err := service.Get(context.Background(), userID, bookingID)
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != bookingID || reader.gotUser != userID || reader.gotBooking != bookingID {
		t.Fatalf("unexpected get delegation: got=%+v user=%s booking=%s", got, reader.gotUser, reader.gotBooking)
	}
}
