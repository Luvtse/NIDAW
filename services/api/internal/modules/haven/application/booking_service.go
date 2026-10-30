// Package application coordinates Haven booking use cases without depending on HTTP or PostgreSQL.
package application

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	havendomain "nidaw-backend/internal/modules/haven/domain"
)

var (
	ErrHotelNotFound         = errors.New("hotel not found")
	ErrHotelNotBookable      = errors.New("hotel is not currently bookable")
	ErrInventoryUnconfigured = errors.New("room inventory is not configured for every requested night")
	ErrInventoryUnavailable  = errors.New("not enough rooms are available for the requested dates")
)

type Booking struct {
	ID          uuid.UUID
	UserID      uuid.UUID
	HotelID     uuid.UUID
	CheckIn     time.Time
	CheckOut    time.Time
	Guests      int
	Rooms       int
	TotalAmount float64
	Currency    string
	Status      string
	CreatedAt   time.Time
}

type CreateBookingCommand struct {
	UserID   uuid.UUID
	HotelID  uuid.UUID
	CheckIn  time.Time
	CheckOut time.Time
	Guests   int
	Rooms    int
	Today    time.Time
}

// BookingWriter owns the atomic persistence boundary, including inventory locking and booking insertion.
type BookingWriter interface {
	CreateBooking(context.Context, CreateBookingCommand) (Booking, error)
}

type BookingReader interface {
	ListBookings(context.Context, uuid.UUID, int) ([]Booking, error)
	GetBooking(context.Context, uuid.UUID, uuid.UUID) (Booking, error)
}

type BookingService struct {
	writer BookingWriter
	reader BookingReader
}

func NewBookingService(writer BookingWriter, readers ...BookingReader) *BookingService {
	s := &BookingService{writer: writer}
	if len(readers) > 0 {
		s.reader = readers[0]
	}
	return s
}

func (s *BookingService) Create(ctx context.Context, cmd CreateBookingCommand) (Booking, error) {
	if s == nil || s.writer == nil {
		return Booking{}, errors.New("Haven booking writer is not configured")
	}
	if err := havendomain.ValidateStay(cmd.CheckIn, cmd.CheckOut, cmd.Today, cmd.Guests, cmd.Rooms); err != nil {
		return Booking{}, err
	}
	return s.writer.CreateBooking(ctx, cmd)
}

var (
	ErrBookingNotFound            = errors.New("booking not found")
	ErrBookingNotCancellable      = errors.New("booking cannot be cancelled in its current state")
	ErrInventoryBelowReservations = errors.New("total rooms cannot be lower than already reserved inventory")
)

type BookingLifecycleWriter interface {
	CancelBooking(context.Context, uuid.UUID, uuid.UUID) error
	SetInventory(context.Context, uuid.UUID, time.Time, int) error
}

// Cancel releases inventory and changes booking state in one persistence transaction.
func (s *BookingService) Cancel(ctx context.Context, userID, bookingID uuid.UUID) error {
	writer, ok := s.writer.(BookingLifecycleWriter)
	if !ok {
		return errors.New("Haven booking lifecycle writer is not configured")
	}
	return writer.CancelBooking(ctx, userID, bookingID)
}

// ConfigureInventory provisions one night's inventory without allowing capacity below reservations.
func (s *BookingService) ConfigureInventory(ctx context.Context, hotelID uuid.UUID, date time.Time, totalRooms int) error {
	if totalRooms < 1 || totalRooms > 10000 {
		return havendomain.ErrInvalidOccupancy
	}
	writer, ok := s.writer.(BookingLifecycleWriter)
	if !ok {
		return errors.New("Haven booking lifecycle writer is not configured")
	}
	return writer.SetInventory(ctx, hotelID, date, totalRooms)
}

// List returns only bookings owned by the requesting user.
func (s *BookingService) List(ctx context.Context, userID uuid.UUID, limit int) ([]Booking, error) {
	if s == nil || s.reader == nil {
		return nil, errors.New("Haven booking reader is not configured")
	}
	if limit < 1 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return s.reader.ListBookings(ctx, userID, limit)
}

// Get returns a booking only when it belongs to the requesting user.
func (s *BookingService) Get(ctx context.Context, userID, bookingID uuid.UUID) (Booking, error) {
	if s == nil || s.reader == nil {
		return Booking{}, errors.New("Haven booking reader is not configured")
	}
	return s.reader.GetBooking(ctx, userID, bookingID)
}
