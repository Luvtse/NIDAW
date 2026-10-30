package ports

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

var (
	ErrEmployeeNotActive   = errors.New("no active corporate employee membership")
	ErrApproverNotFound    = errors.New("no eligible corporate approver")
	ErrApprovalNotAssigned = errors.New("booking approval is not assigned to this user")
	ErrBookingNotPending   = errors.New("booking is not pending approval")
)

// BookingEvent is persisted alongside a booking so delivery can be retried
// without making booking creation depend on broker availability.
type BookingEvent struct {
	SchemaVersion int
	Type          string
	Topic         string
	Payload       map[string]interface{}
	Timestamp     int64
}

type BookingRecord struct {
	ID               uuid.UUID
	EmployeeID       uuid.UUID
	CorporateID      uuid.UUID
	ServiceType      entities.ServiceType
	BookingData      map[string]interface{}
	PaymentMethod    string
	Status           string
	PolicyCompliant  bool
	Violations       []string
	EstimatedAmount  float64
	RequiresApproval bool
	ApproverID       *uuid.UUID
}

type BookingRepository interface {
	FindActiveEmployee(ctx context.Context, employeeID, corporateID uuid.UUID) (*entities.Employee, error)
	FindActivePolicy(ctx context.Context, corporateID uuid.UUID) (*entities.TravelPolicy, error)
	FindApprover(ctx context.Context, corporateID uuid.UUID, minimumLevel int) (*uuid.UUID, error)
	CreateBookingWithEvents(ctx context.Context, booking BookingRecord, events []BookingEvent) error
	DecideBooking(ctx context.Context, bookingID, approverUserID uuid.UUID, approve bool, notes string) error
}
