// Package postgres adapts Haven's booking use case to PostgreSQL transactions.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/haven/application"
	havendomain "nidaw-backend/internal/modules/haven/domain"
	"nidaw-backend/internal/shared/database"
)

type BookingWriter struct{ db *database.Postgres }

func NewBookingWriter(db *database.Postgres) *BookingWriter { return &BookingWriter{db: db} }

func (w *BookingWriter) CreateBooking(ctx context.Context, cmd application.CreateBookingCommand) (application.Booking, error) {
	var result application.Booking
	tx, err := w.db.Pool().Begin(ctx)
	if err != nil {
		return result, fmt.Errorf("begin booking transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var nightly float64
	var currency, status string
	err = tx.QueryRow(ctx, `SELECT COALESCE(price_per_night,0), COALESCE(currency,'USD'), COALESCE(status,'inactive') FROM hotels WHERE id=$1 FOR UPDATE`, cmd.HotelID).Scan(&nightly, &currency, &status)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return result, application.ErrHotelNotFound
		}
		return result, fmt.Errorf("load hotel pricing: %w", err)
	}
	if status != "active" || nightly <= 0 {
		return result, application.ErrHotelNotBookable
	}

	rows, err := tx.Query(ctx, `SELECT inventory_date,total_rooms,reserved_rooms FROM hotel_room_inventory WHERE hotel_id=$1 AND inventory_date >= $2 AND inventory_date < $3 ORDER BY inventory_date FOR UPDATE`, cmd.HotelID, cmd.CheckIn, cmd.CheckOut)
	if err != nil {
		return result, fmt.Errorf("query room inventory: %w", err)
	}
	type nightInventory struct {
		date            time.Time
		total, reserved int
	}
	inventory := make([]nightInventory, 0)
	for rows.Next() {
		var n nightInventory
		if err := rows.Scan(&n.date, &n.total, &n.reserved); err != nil {
			rows.Close()
			return result, fmt.Errorf("scan room inventory: %w", err)
		}
		inventory = append(inventory, n)
	}
	rowsErr := rows.Err()
	rows.Close()
	if rowsErr != nil {
		return result, fmt.Errorf("read room inventory: %w", rowsErr)
	}
	nights := havendomain.StayNights(cmd.CheckIn, cmd.CheckOut)
	if len(inventory) != nights {
		return result, application.ErrInventoryUnconfigured
	}
	for _, n := range inventory {
		if n.total-n.reserved < cmd.Rooms {
			return result, application.ErrInventoryUnavailable
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE hotel_room_inventory SET reserved_rooms=reserved_rooms+$4,updated_at=NOW() WHERE hotel_id=$1 AND inventory_date >= $2 AND inventory_date < $3`, cmd.HotelID, cmd.CheckIn, cmd.CheckOut, cmd.Rooms); err != nil {
		return result, fmt.Errorf("reserve room inventory: %w", err)
	}
	total, err := havendomain.BookingTotal(nightly, nights, cmd.Rooms)
	if err != nil {
		return result, err
	}
	err = tx.QueryRow(ctx, `INSERT INTO bookings(user_id,hotel_id,check_in,check_out,guests,rooms,total_amount,currency,status) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'pending') RETURNING id,user_id,hotel_id,check_in,check_out,guests,rooms,total_amount,currency,status,created_at`, cmd.UserID, cmd.HotelID, cmd.CheckIn, cmd.CheckOut, cmd.Guests, cmd.Rooms, total, currency).Scan(&result.ID, &result.UserID, &result.HotelID, &result.CheckIn, &result.CheckOut, &result.Guests, &result.Rooms, &result.TotalAmount, &result.Currency, &result.Status, &result.CreatedAt)
	if err != nil {
		return result, fmt.Errorf("insert booking: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return result, fmt.Errorf("commit booking: %w", err)
	}
	return result, nil
}

// CancelBooking locks the user's booking and atomically releases its reserved inventory.
func (w *BookingWriter) CancelBooking(ctx context.Context, userID, bookingID uuid.UUID) error {
	tx, err := w.db.Pool().Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin cancellation transaction: %w", err)
	}
	defer tx.Rollback(ctx)
	var hotelID uuid.UUID
	var checkIn, checkOut time.Time
	var rooms int
	var status string
	err = tx.QueryRow(ctx, `SELECT hotel_id,check_in,check_out,rooms,status FROM bookings WHERE id=$1 AND user_id=$2 FOR UPDATE`, bookingID, userID).Scan(&hotelID, &checkIn, &checkOut, &rooms, &status)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return application.ErrBookingNotFound
		}
		return fmt.Errorf("load booking for cancellation: %w", err)
	}
	if status != "pending" && status != "confirmed" {
		return application.ErrBookingNotCancellable
	}
	if _, err = tx.Exec(ctx, `UPDATE hotel_room_inventory SET reserved_rooms=GREATEST(0,reserved_rooms-$4),updated_at=NOW() WHERE hotel_id=$1 AND inventory_date >= $2 AND inventory_date < $3`, hotelID, checkIn, checkOut, rooms); err != nil {
		return fmt.Errorf("release room inventory: %w", err)
	}
	if _, err = tx.Exec(ctx, `UPDATE bookings SET status='cancelled',updated_at=NOW() WHERE id=$1`, bookingID); err != nil {
		return fmt.Errorf("cancel booking: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit cancellation: %w", err)
	}
	return nil
}

// SetInventory uses a conditional upsert to preserve the invariant reserved_rooms <= total_rooms.
func (w *BookingWriter) SetInventory(ctx context.Context, hotelID uuid.UUID, date time.Time, totalRooms int) error {
	cmd, err := w.db.Exec(ctx, `INSERT INTO hotel_room_inventory(hotel_id,inventory_date,total_rooms) VALUES($1,$2,$3) ON CONFLICT(hotel_id,inventory_date) DO UPDATE SET total_rooms=EXCLUDED.total_rooms,updated_at=NOW() WHERE hotel_room_inventory.reserved_rooms <= EXCLUDED.total_rooms`, hotelID, date, totalRooms)
	if err != nil {
		return fmt.Errorf("configure room inventory: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return application.ErrInventoryBelowReservations
	}
	return nil
}

// ListBookings reads a user's bookings without exposing SQL to the HTTP adapter.
func (w *BookingWriter) ListBookings(ctx context.Context, userID uuid.UUID, limit int) ([]application.Booking, error) {
	rows, err := w.db.Query(ctx, `SELECT id,user_id,hotel_id,check_in,check_out,guests,rooms,total_amount,currency,status,created_at FROM bookings WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("query bookings: %w", err)
	}
	defer rows.Close()
	items := make([]application.Booking, 0)
	for rows.Next() {
		var b application.Booking
		if err := rows.Scan(&b.ID, &b.UserID, &b.HotelID, &b.CheckIn, &b.CheckOut, &b.Guests, &b.Rooms, &b.TotalAmount, &b.Currency, &b.Status, &b.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan booking: %w", err)
		}
		items = append(items, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bookings: %w", err)
	}
	return items, nil
}

// GetBooking enforces ownership in the query itself.
func (w *BookingWriter) GetBooking(ctx context.Context, userID, bookingID uuid.UUID) (application.Booking, error) {
	var b application.Booking
	err := w.db.QueryRow(ctx, `SELECT id,user_id,hotel_id,check_in,check_out,guests,rooms,total_amount,currency,status,created_at FROM bookings WHERE id=$1 AND user_id=$2`, bookingID, userID).Scan(&b.ID, &b.UserID, &b.HotelID, &b.CheckIn, &b.CheckOut, &b.Guests, &b.Rooms, &b.TotalAmount, &b.Currency, &b.Status, &b.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return application.Booking{}, application.ErrBookingNotFound
		}
		return application.Booking{}, fmt.Errorf("load booking: %w", err)
	}
	return b, nil
}
