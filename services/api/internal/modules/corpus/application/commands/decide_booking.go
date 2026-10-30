package commands

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/application/ports"
)

// DecideCorporateBookingHandler records an explicit approval decision. The
// repository atomically updates the booking and appends its outbound event.
type DecideCorporateBookingHandler struct{ repository ports.BookingRepository }

func NewDecideCorporateBookingHandler(repository ports.BookingRepository) *DecideCorporateBookingHandler {
	return &DecideCorporateBookingHandler{repository: repository}
}

func (h *DecideCorporateBookingHandler) Execute(ctx context.Context, bookingID, approverUserID uuid.UUID, approve bool, notes string) error {
	if h == nil || h.repository == nil {
		return errors.New("corpus booking repository is required")
	}
	if bookingID == uuid.Nil || approverUserID == uuid.Nil {
		return errors.New("booking and authenticated approver identifiers are required")
	}
	notes = strings.TrimSpace(notes)
	if len(notes) > 2000 {
		return errors.New("approval notes must not exceed 2000 characters")
	}
	return h.repository.DecideBooking(ctx, bookingID, approverUserID, approve, notes)
}
