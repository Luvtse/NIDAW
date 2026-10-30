package http

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	corpuscommands "nidaw-backend/internal/modules/corpus/application/commands"
	"nidaw-backend/internal/modules/corpus/domain/entities"
	"nidaw-backend/internal/shared/auth"
)

type bookingCreatorFake struct {
	command *corpuscommands.CreateCorporateBookingCommand
	result  *corpuscommands.CorporateBookingResult
	err     error
}

func (f *bookingCreatorFake) Execute(_ context.Context, cmd *corpuscommands.CreateCorporateBookingCommand) (*corpuscommands.CorporateBookingResult, error) {
	f.command = cmd
	return f.result, f.err
}

func TestCreateBookingRequiresAuthenticatedUser(t *testing.T) {
	h := &Handler{createBooking: &bookingCreatorFake{}}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/corpus/bookings", strings.NewReader(`{}`))
	res := httptest.NewRecorder()
	h.CreateBooking(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.Code)
	}
}

func TestCreateBookingDerivesUserFromContextAndRejectsEmployeeIDField(t *testing.T) {
	userID := uuid.New()
	corporateID := uuid.New()
	fake := &bookingCreatorFake{result: &corpuscommands.CorporateBookingResult{BookingID: uuid.New(), Status: "confirmed"}}
	h := &Handler{createBooking: fake}
	body := `{"corporate_id":"` + corporateID.String() + `","service_type":"rides","booking_data":{"amount":20,"fare":20,"ride_type":"standard","requested_at":"2026-10-24T10:00:00Z"},"employee_id":"` + uuid.NewString() + `"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/corpus/bookings", strings.NewReader(body))
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))
	res := httptest.NewRecorder()
	h.CreateBooking(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected unknown employee_id field to be rejected, got %d: %s", res.Code, res.Body.String())
	}
	if fake.command != nil {
		t.Fatal("invalid request must not invoke booking application")
	}
}

func TestCreateBookingPassesAuthenticatedUserToApplication(t *testing.T) {
	userID := uuid.New()
	corporateID := uuid.New()
	fake := &bookingCreatorFake{result: &corpuscommands.CorporateBookingResult{BookingID: uuid.New(), Status: "confirmed"}}
	h := &Handler{createBooking: fake}
	body := `{"corporate_id":"` + corporateID.String() + `","service_type":"rides","booking_data":{"amount":20,"fare":20,"ride_type":"standard","requested_at":"2026-10-24T10:00:00Z"}}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/corpus/bookings", strings.NewReader(body))
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, userID))
	res := httptest.NewRecorder()
	h.CreateBooking(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", res.Code, res.Body.String())
	}
	if fake.command == nil || fake.command.UserID != userID || fake.command.CorporateID != corporateID || fake.command.ServiceType != entities.ServiceRides {
		t.Fatalf("unexpected command passed to application: %+v", fake.command)
	}
}

func TestCreateBookingDoesNotLeakInternalErrors(t *testing.T) {
	fake := &bookingCreatorFake{err: errors.New("database password leaked")}
	h := &Handler{createBooking: fake}
	body := `{"corporate_id":"` + uuid.NewString() + `","service_type":"rides","booking_data":{"amount":20,"fare":20,"ride_type":"standard","requested_at":"2026-10-24T10:00:00Z"}}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/corpus/bookings", strings.NewReader(body))
	req = req.WithContext(context.WithValue(req.Context(), auth.UserIDKey, uuid.New()))
	res := httptest.NewRecorder()
	h.CreateBooking(res, req)
	if strings.Contains(res.Body.String(), "database password leaked") {
		t.Fatal("internal error leaked to HTTP response")
	}
}
