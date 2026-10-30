// Package domain contains Haven's business rules independent of HTTP and persistence.
package domain

import (
	"errors"
	"time"
)

var (
	ErrInvalidStay        = errors.New("check-out must be after check-in")
	ErrStayInPast         = errors.New("check-in cannot be in the past")
	ErrInvalidOccupancy   = errors.New("guests must be 1-20 and rooms must be 1-10")
	ErrInvalidNightlyRate = errors.New("nightly rate must be positive")
)

// ValidateStay enforces the date and occupancy rules for a Haven reservation.
// Dates are interpreted as calendar dates in UTC, matching the API's YYYY-MM-DD contract.
func ValidateStay(checkIn, checkOut, today time.Time, guests, rooms int) error {
	if !checkOut.After(checkIn) {
		return ErrInvalidStay
	}
	if guests < 1 || guests > 20 || rooms < 1 || rooms > 10 {
		return ErrInvalidOccupancy
	}
	if calendarDate(checkIn).Before(calendarDate(today)) {
		return ErrStayInPast
	}
	return nil
}

// StayNights returns the number of calendar nights in a validated date-only stay.
func StayNights(checkIn, checkOut time.Time) int {
	return int(calendarDate(checkOut).Sub(calendarDate(checkIn)).Hours() / 24)
}

// BookingTotal calculates the immutable price snapshot for a reservation.
func BookingTotal(nightlyRate float64, nights, rooms int) (float64, error) {
	if nightlyRate <= 0 {
		return 0, ErrInvalidNightlyRate
	}
	if nights < 1 || rooms < 1 {
		return 0, ErrInvalidStay
	}
	return nightlyRate * float64(nights) * float64(rooms), nil
}

func calendarDate(value time.Time) time.Time {
	y, m, d := value.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
