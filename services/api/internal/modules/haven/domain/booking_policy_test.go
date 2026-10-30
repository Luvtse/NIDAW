package domain

import (
	"errors"
	"testing"
	"time"
)

func day(s string) time.Time {
	v, err := time.Parse("2006-01-02", s)
	if err != nil {
		panic(err)
	}
	return v
}

func TestValidateStay(t *testing.T) {
	today := day("2026-10-23")
	tests := []struct {
		name          string
		in, out       time.Time
		guests, rooms int
		want          error
	}{
		{"valid", day("2026-10-23"), day("2026-10-25"), 2, 1, nil},
		{"checkout before checkin", day("2026-10-25"), day("2026-10-25"), 2, 1, ErrInvalidStay},
		{"past checkin", day("2026-10-22"), day("2026-10-24"), 2, 1, ErrStayInPast},
		{"zero guests", day("2026-10-23"), day("2026-10-24"), 0, 1, ErrInvalidOccupancy},
		{"too many rooms", day("2026-10-23"), day("2026-10-24"), 2, 11, ErrInvalidOccupancy},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateStay(tt.in, tt.out, today, tt.guests, tt.rooms)
			if !errors.Is(err, tt.want) {
				t.Fatalf("ValidateStay() error = %v, want %v", err, tt.want)
			}
		})
	}
}

func TestBookingTotal(t *testing.T) {
	got, err := BookingTotal(125, 3, 2)
	if err != nil {
		t.Fatal(err)
	}
	if got != 750 {
		t.Fatalf("BookingTotal() = %v, want 750", got)
	}
	if _, err := BookingTotal(0, 1, 1); !errors.Is(err, ErrInvalidNightlyRate) {
		t.Fatalf("expected invalid rate error, got %v", err)
	}
}
