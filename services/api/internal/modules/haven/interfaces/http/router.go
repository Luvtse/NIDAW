// Package http implements Haven's accommodation discovery and booking API.
// It is part of the in-process modular monolith; it is not a separate service.
package http

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	havenapp "nidaw-backend/internal/modules/haven/application"
	havendomain "nidaw-backend/internal/modules/haven/domain"
	havenpostgres "nidaw-backend/internal/modules/haven/infrastructure/postgres"
	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/middleware"
)

type Handler struct {
	bookingService *havenapp.BookingService
	catalogService *havenapp.CatalogService
}

func NewHandler(db *database.Postgres) *Handler {
	writer := havenpostgres.NewBookingWriter(db)
	catalog := havenpostgres.NewHotelCatalog(db)
	return &Handler{bookingService: havenapp.NewBookingService(writer, writer), catalogService: havenapp.NewCatalogService(catalog)}
}

func RegisterRoutes(r chi.Router, db *database.Postgres, authService *auth.Service) {
	h := NewHandler(db)
	r.Route("/api/v1/haven", func(hr chi.Router) {
		hr.Get("/hotels", h.ListHotels)
		hr.Get("/hotels/{hotelID}", h.GetHotel)
		hr.Group(func(pr chi.Router) {
			pr.Use(middleware.AuthRequired(authService))
			pr.Use(middleware.ExtractUserToContext)
			pr.Put("/hotels/{hotelID}/inventory/{date}", h.SetInventory)
			pr.Post("/bookings", h.CreateBooking)
			pr.Get("/bookings", h.ListBookings)
			pr.Get("/bookings/{bookingID}", h.GetBooking)
			pr.Post("/bookings/{bookingID}/cancel", h.CancelBooking)
		})
	})
}

type hotel struct {
	ID            uuid.UUID       `json:"id"`
	Name          string          `json:"name"`
	Description   *string         `json:"description,omitempty"`
	CountryCode   string          `json:"country_code"`
	City          string          `json:"city"`
	Address       *string         `json:"address,omitempty"`
	Latitude      *float64        `json:"latitude,omitempty"`
	Longitude     *float64        `json:"longitude,omitempty"`
	StarRating    *int            `json:"star_rating,omitempty"`
	PricePerNight *float64        `json:"price_per_night,omitempty"`
	Currency      string          `json:"currency"`
	Amenities     json.RawMessage `json:"amenities"`
	Images        json.RawMessage `json:"images"`
}

func (h *Handler) ListHotels(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	items, err := h.catalogService.ListHotels(r.Context(), havenapp.HotelFilter{
		City:        strings.TrimSpace(q.Get("city")),
		CountryCode: strings.ToUpper(strings.TrimSpace(q.Get("country_code"))),
		Limit:       parseLimit(q.Get("limit"), 20, 100),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not search hotels")
		return
	}
	out := make([]hotel, 0, len(items))
	for _, item := range items {
		out = append(out, toHTTPHotel(item))
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out, "count": len(out)})
}

func (h *Handler) GetHotel(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "hotelID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid hotel id")
		return
	}
	item, err := h.catalogService.GetHotel(r.Context(), id)
	if err != nil {
		if errors.Is(err, havenapp.ErrHotelNotFound) {
			writeError(w, http.StatusNotFound, "hotel not found")
		} else {
			writeError(w, http.StatusInternalServerError, "could not load hotel")
		}
		return
	}
	writeJSON(w, http.StatusOK, toHTTPHotel(item))
}

func toHTTPHotel(item havenapp.Hotel) hotel {
	return hotel{ID: item.ID, Name: item.Name, Description: item.Description, CountryCode: item.CountryCode, City: item.City, Address: item.Address, Latitude: item.Latitude, Longitude: item.Longitude, StarRating: item.StarRating, PricePerNight: item.PricePerNight, Currency: item.Currency, Amenities: nonEmptyJSON(item.Amenities, `[]`), Images: nonEmptyJSON(item.Images, `[]`)}
}

type createBookingRequest struct {
	HotelID  string `json:"hotel_id"`
	CheckIn  string `json:"check_in"`
	CheckOut string `json:"check_out"`
	Guests   int    `json:"guests"`
	Rooms    int    `json:"rooms"`
}
type booking struct {
	ID          uuid.UUID `json:"id"`
	UserID      uuid.UUID `json:"user_id"`
	HotelID     uuid.UUID `json:"hotel_id"`
	CheckIn     time.Time `json:"check_in"`
	CheckOut    time.Time `json:"check_out"`
	Guests      int       `json:"guests"`
	Rooms       int       `json:"rooms"`
	TotalAmount float64   `json:"total_amount"`
	Currency    string    `json:"currency"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

func (h *Handler) CreateBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	var req createBookingRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16*1024)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	hotelID, err := uuid.Parse(req.HotelID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "hotel_id must be a UUID")
		return
	}
	checkIn, err := time.Parse("2006-01-02", req.CheckIn)
	if err != nil {
		writeError(w, http.StatusBadRequest, "check_in must use YYYY-MM-DD")
		return
	}
	checkOut, err := time.Parse("2006-01-02", req.CheckOut)
	if err != nil {
		writeError(w, http.StatusBadRequest, "check_out must use YYYY-MM-DD")
		return
	}
	createdBooking, createErr := h.bookingService.Create(r.Context(), havenapp.CreateBookingCommand{
		UserID: userID, HotelID: hotelID, CheckIn: checkIn, CheckOut: checkOut,
		Guests: req.Guests, Rooms: req.Rooms, Today: time.Now().UTC(),
	})
	if createErr != nil {
		switch {
		case errors.Is(createErr, havenapp.ErrHotelNotFound):
			writeError(w, http.StatusNotFound, "hotel not found")
		case errors.Is(createErr, havenapp.ErrHotelNotBookable):
			writeError(w, http.StatusConflict, "hotel is not currently bookable")
		case errors.Is(createErr, havenapp.ErrInventoryUnconfigured):
			writeError(w, http.StatusConflict, "room inventory is not configured for every requested night")
		case errors.Is(createErr, havenapp.ErrInventoryUnavailable):
			writeError(w, http.StatusConflict, "not enough rooms are available for the requested dates")
		case errors.Is(createErr, havendomain.ErrInvalidStay), errors.Is(createErr, havendomain.ErrStayInPast), errors.Is(createErr, havendomain.ErrInvalidOccupancy):
			writeError(w, http.StatusBadRequest, createErr.Error())
		default:
			writeError(w, http.StatusInternalServerError, "could not create booking")
		}
		return
	}
	created := booking{
		ID: createdBooking.ID, UserID: createdBooking.UserID, HotelID: createdBooking.HotelID,
		CheckIn: createdBooking.CheckIn, CheckOut: createdBooking.CheckOut, Guests: createdBooking.Guests,
		Rooms: createdBooking.Rooms, TotalAmount: createdBooking.TotalAmount, Currency: createdBooking.Currency,
		Status: createdBooking.Status, CreatedAt: createdBooking.CreatedAt,
	}
	writeJSON(w, http.StatusCreated, created)
}

func (h *Handler) ListBookings(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	items, err := h.bookingService.List(r.Context(), userID, parseLimit(r.URL.Query().Get("limit"), 20, 100))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list bookings")
		return
	}
	out := make([]booking, 0, len(items))
	for _, b := range items {
		out = append(out, toHTTPBooking(b))
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out, "count": len(out)})
}

func (h *Handler) GetBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "bookingID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid booking id")
		return
	}
	b, err := h.bookingService.Get(r.Context(), userID, id)
	if err != nil {
		if errors.Is(err, havenapp.ErrBookingNotFound) {
			writeError(w, http.StatusNotFound, "booking not found")
		} else {
			writeError(w, http.StatusInternalServerError, "could not load booking")
		}
		return
	}
	writeJSON(w, http.StatusOK, toHTTPBooking(b))
}

func toHTTPBooking(b havenapp.Booking) booking {
	return booking{ID: b.ID, UserID: b.UserID, HotelID: b.HotelID, CheckIn: b.CheckIn, CheckOut: b.CheckOut, Guests: b.Guests, Rooms: b.Rooms, TotalAmount: b.TotalAmount, Currency: b.Currency, Status: b.Status, CreatedAt: b.CreatedAt}
}

func (h *Handler) CancelBooking(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "bookingID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid booking id")
		return
	}
	if err := h.bookingService.Cancel(r.Context(), userID, id); err != nil {
		switch {
		case errors.Is(err, havenapp.ErrBookingNotFound):
			writeError(w, http.StatusNotFound, "booking not found")
		case errors.Is(err, havenapp.ErrBookingNotCancellable):
			writeError(w, http.StatusConflict, "booking cannot be cancelled in its current state")
		default:
			writeError(w, http.StatusInternalServerError, "could not cancel booking")
		}
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// SetInventory lets an authenticated platform administrator provision inventory
// explicitly. Existing hotels are not assigned guessed room counts by migration.
func (h *Handler) SetInventory(w http.ResponseWriter, r *http.Request) {
	role, ok := auth.GetUserRoleFromContext(r.Context())
	if !ok || (role != "admin" && role != "super_admin") {
		writeError(w, http.StatusForbidden, "administrator role required")
		return
	}
	hotelID, err := uuid.Parse(chi.URLParam(r, "hotelID"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid hotel id")
		return
	}
	inventoryDate, err := time.Parse("2006-01-02", chi.URLParam(r, "date"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "date must use YYYY-MM-DD")
		return
	}
	var req struct {
		TotalRooms int `json:"total_rooms"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8*1024)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.TotalRooms < 1 || req.TotalRooms > 10000 {
		writeError(w, http.StatusBadRequest, "total_rooms must be between 1 and 10000")
		return
	}
	err = h.bookingService.ConfigureInventory(r.Context(), hotelID, inventoryDate, req.TotalRooms)
	if err != nil {
		if errors.Is(err, havenapp.ErrInventoryBelowReservations) {
			writeError(w, http.StatusConflict, "total_rooms cannot be lower than already reserved inventory")
		} else {
			writeError(w, http.StatusInternalServerError, "could not configure inventory")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"hotel_id": hotelID, "date": inventoryDate.Format("2006-01-02"), "total_rooms": req.TotalRooms})
}

func parseLimit(s string, fallback, max int) int {
	n, err := strconv.Atoi(s)
	if err != nil || n < 1 {
		return fallback
	}
	if n > max {
		return max
	}
	return n
}
func nonEmptyJSON(b []byte, fallback string) json.RawMessage {
	if len(b) == 0 {
		return json.RawMessage(fallback)
	}
	return json.RawMessage(b)
}
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
