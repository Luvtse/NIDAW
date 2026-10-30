// Package http exposes Corpus corporate booking operations through the API.
// Employee identity is always derived from the authenticated token, never from
// a client-supplied employee identifier.
package http

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	corpuscommands "nidaw-backend/internal/modules/corpus/application/commands"
	"nidaw-backend/internal/modules/corpus/application/ports"
	"nidaw-backend/internal/modules/corpus/domain/entities"
	corpuspostgres "nidaw-backend/internal/modules/corpus/infrastructure/postgres"
	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/middleware"
)

type bookingCreator interface {
	Execute(context.Context, *corpuscommands.CreateCorporateBookingCommand) (*corpuscommands.CorporateBookingResult, error)
}

type bookingDecider interface {
	Execute(context.Context, uuid.UUID, uuid.UUID, bool, string) error
}

type Handler struct {
	createBooking bookingCreator
	decideBooking bookingDecider
}

func NewHandler(db *database.Postgres) *Handler {
	repository := corpuspostgres.NewBookingRepository(db)
	return &Handler{createBooking: corpuscommands.NewCreateCorporateBookingHandler(repository), decideBooking: corpuscommands.NewDecideCorporateBookingHandler(repository)}
}

func RegisterRoutes(r chi.Router, db *database.Postgres, authService *auth.Service) {
	h := NewHandler(db)
	r.Route("/api/v1/corpus", func(cr chi.Router) {
		cr.Group(func(pr chi.Router) {
			pr.Use(middleware.AuthRequired(authService))
			pr.Use(middleware.ExtractUserToContext)
			pr.Post("/bookings", h.CreateBooking)
			pr.Post("/bookings/{bookingID}/approve", h.ApproveBooking)
			pr.Post("/bookings/{bookingID}/reject", h.RejectBooking)
		})
	})
}

type createBookingRequest struct {
	CorporateID   string                 `json:"corporate_id"`
	ServiceType   string                 `json:"service_type"`
	BookingData   map[string]interface{} `json:"booking_data"`
	PaymentMethod string                 `json:"payment_method"`
}

type bookingResponse struct {
	BookingID        uuid.UUID  `json:"booking_id"`
	Status           string     `json:"status"`
	PolicyCompliant  bool       `json:"policy_compliant"`
	Violations       []string   `json:"violations"`
	RequiresApproval bool       `json:"requires_approval"`
	ApproverID       *uuid.UUID `json:"approver_id,omitempty"`
	EstimatedAmount  float64    `json:"estimated_amount"`
}

func (h *Handler) CreateBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok || userID == uuid.Nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	if h == nil || h.createBooking == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "Corpus booking is unavailable"})
		return
	}

	var req createBookingRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 256*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON request"})
		return
	}
	var trailing interface{}
	if err := decoder.Decode(&trailing); err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "request must contain a single valid JSON object"})
		return
	}
	corporateID, err := uuid.Parse(strings.TrimSpace(req.CorporateID))
	if err != nil || corporateID == uuid.Nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "corporate_id must be a valid UUID"})
		return
	}
	serviceType := entitiesServiceType(strings.TrimSpace(req.ServiceType))
	if !serviceType.Valid() {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_type must be rides, hotels, food, or freight"})
		return
	}
	if req.BookingData == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "booking_data is required"})
		return
	}

	result, err := h.createBooking.Execute(r.Context(), &corpuscommands.CreateCorporateBookingCommand{
		UserID: userID, CorporateID: corporateID, ServiceType: serviceType.Value(),
		BookingData: req.BookingData, PaymentMethod: strings.TrimSpace(req.PaymentMethod),
	})
	if err != nil {
		status := http.StatusUnprocessableEntity
		message := "booking request could not be processed"
		if errors.Is(err, ports.ErrEmployeeNotActive) || strings.Contains(err.Error(), "employee not found or inactive") {
			status, message = http.StatusForbidden, "no active employee membership exists for this corporate account"
		} else if strings.Contains(err.Error(), "repository") || strings.Contains(err.Error(), "database") || strings.Contains(err.Error(), "load active") || strings.Contains(err.Error(), "load corporate employee") || strings.Contains(err.Error(), "resolve corporate") || strings.Contains(err.Error(), "persist") {
			status, message = http.StatusInternalServerError, "could not create corporate booking"
		}
		writeJSON(w, status, map[string]string{"error": message})
		return
	}
	writeJSON(w, http.StatusCreated, bookingResponse{
		BookingID: result.BookingID, Status: result.Status, PolicyCompliant: result.PolicyCompliant,
		Violations: result.Violations, RequiresApproval: result.RequiresApproval,
		ApproverID: result.ApproverID, EstimatedAmount: result.EstimatedAmount,
	})
}

type decisionRequest struct {
	Notes string `json:"notes"`
}

func (h *Handler) ApproveBooking(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, true)
}

func (h *Handler) RejectBooking(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, false)
}

func (h *Handler) decide(w http.ResponseWriter, r *http.Request, approve bool) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok || userID == uuid.Nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}
	if h == nil || h.decideBooking == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "Corpus approval is unavailable"})
		return
	}
	bookingID, err := uuid.Parse(strings.TrimSpace(chi.URLParam(r, "bookingID")))
	if err != nil || bookingID == uuid.Nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bookingID must be a valid UUID"})
		return
	}
	var req decisionRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON request"})
		return
	}
	var trailing interface{}
	if err := decoder.Decode(&trailing); err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "request must contain a single valid JSON object"})
		return
	}
	if len(req.Notes) > 2000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "notes must not exceed 2000 characters"})
		return
	}
	if err := h.decideBooking.Execute(r.Context(), bookingID, userID, approve, req.Notes); err != nil {
		switch {
		case errors.Is(err, ports.ErrApprovalNotAssigned):
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "this approval is not assigned to the authenticated user"})
		case errors.Is(err, ports.ErrBookingNotPending):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "booking is no longer pending approval"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "could not record booking decision"})
		}
		return
	}
	state := "rejected"
	if approve {
		state = "approved"
	}
	writeJSON(w, http.StatusOK, map[string]string{"booking_id": bookingID.String(), "decision": state})
}

// serviceType keeps transport parsing separate from the application entities.
type serviceType string

func entitiesServiceType(value string) serviceType { return serviceType(value) }
func (s serviceType) Valid() bool {
	switch s {
	case "rides", "hotels", "food", "freight":
		return true
	default:
		return false
	}
}
func (s serviceType) Value() entities.ServiceType { return entities.ServiceType(s) }

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
