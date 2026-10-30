package commands

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/application/ports"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

type bookingRepositoryFake struct {
	employee    *entities.Employee
	policy      *entities.TravelPolicy
	approver    *uuid.UUID
	approverErr error
	booking     ports.BookingRecord
	events      []ports.BookingEvent
	createErr   error
	created     bool
	decisionErr error
	decisions   int
}

func (f *bookingRepositoryFake) FindActiveEmployee(context.Context, uuid.UUID, uuid.UUID) (*entities.Employee, error) {
	return f.employee, nil
}
func (f *bookingRepositoryFake) FindActivePolicy(context.Context, uuid.UUID) (*entities.TravelPolicy, error) {
	return f.policy, nil
}
func (f *bookingRepositoryFake) FindApprover(context.Context, uuid.UUID, int) (*uuid.UUID, error) {
	return f.approver, f.approverErr
}
func (f *bookingRepositoryFake) CreateBookingWithEvents(_ context.Context, b ports.BookingRecord, events []ports.BookingEvent) error {
	f.booking, f.events, f.created = b, events, true
	return f.createErr
}
func (f *bookingRepositoryFake) DecideBooking(context.Context, uuid.UUID, uuid.UUID, bool, string) error {
	f.decisions++
	return f.decisionErr
}

func newBookingTestRepository() *bookingRepositoryFake {
	return &bookingRepositoryFake{
		employee: &entities.Employee{ID: uuid.New(), SpendingLimit: 1000},
		policy:   &entities.TravelPolicy{RidePolicy: entities.RidePolicy{MaxFarePerRide: 100, AllowedRideTypes: []string{"standard"}}},
	}
}

func TestCreateBookingPersistsBookingAndEventsThroughRepository(t *testing.T) {
	repo := newBookingTestRepository()
	handler := NewCreateCorporateBookingHandler(repo)
	cmd := &CreateCorporateBookingCommand{
		UserID: uuid.New(), CorporateID: uuid.New(), ServiceType: entities.ServiceRides,
		BookingData:   map[string]interface{}{"amount": 20.0, "fare": 20.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z"},
		PaymentMethod: "corporate_account",
	}
	result, err := handler.Execute(context.Background(), cmd)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if !repo.created {
		t.Fatal("expected repository to persist booking and events")
	}
	if result.BookingID != repo.booking.ID || repo.booking.Status != "confirmed" {
		t.Fatalf("unexpected persisted booking: %+v", repo.booking)
	}
	if repo.booking.EmployeeID != repo.employee.ID {
		t.Fatalf("booking must persist resolved employee membership ID, got %s want %s", repo.booking.EmployeeID, repo.employee.ID)
	}
	if len(repo.events) != 2 {
		t.Fatalf("expected created and downstream events, got %d", len(repo.events))
	}
	if repo.events[0].Type != "corpus.booking.created" || repo.events[1].Topic != "nidus.rides" {
		t.Fatalf("unexpected events: %+v", repo.events)
	}
	if repo.events[0].SchemaVersion != 1 || repo.events[1].SchemaVersion != 1 {
		t.Fatalf("new Corpus events must declare schema version 1: %+v", repo.events)
	}
}

func TestCreateBookingFailsClosedWhenApproverMissing(t *testing.T) {
	repo := newBookingTestRepository()
	repo.employee.SpendingLimit = 10
	handler := NewCreateCorporateBookingHandler(repo)
	cmd := &CreateCorporateBookingCommand{
		UserID: uuid.New(), CorporateID: uuid.New(), ServiceType: entities.ServiceRides,
		BookingData: map[string]interface{}{"amount": 20.0, "fare": 20.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z"},
	}
	_, err := handler.Execute(context.Background(), cmd)
	if err == nil || !strings.Contains(err.Error(), "no eligible approver") {
		t.Fatalf("expected fail-closed approval error, got %v", err)
	}
	if repo.created {
		t.Fatal("booking must not persist without an approver")
	}
}

func TestCreateBookingReturnsPersistenceError(t *testing.T) {
	repo := newBookingTestRepository()
	repo.createErr = errors.New("transaction failed")
	result, err := NewCreateCorporateBookingHandler(repo).Execute(context.Background(), &CreateCorporateBookingCommand{
		UserID: uuid.New(), CorporateID: uuid.New(), ServiceType: entities.ServiceRides,
		BookingData: map[string]interface{}{"amount": 20.0, "fare": 20.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z"},
	})
	if err == nil || result != nil {
		t.Fatalf("expected persistence error and nil result, result=%+v err=%v", result, err)
	}
}
