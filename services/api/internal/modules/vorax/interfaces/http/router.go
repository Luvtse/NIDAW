// Package http implements Vorax's restaurant discovery, menu, and food-order API.
// The module shares the Go process and database infrastructure with the monolith.
package http

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	voraxapp "nidaw-backend/internal/modules/vorax/application"
	voraxdomain "nidaw-backend/internal/modules/vorax/domain"
	voraxpostgres "nidaw-backend/internal/modules/vorax/infrastructure/postgres"
	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/middleware"
)

type Handler struct {
	orderService *voraxapp.OrderService
	readService  *voraxapp.ReadService
}

func NewHandler(db *database.Postgres) *Handler {
	readers := voraxpostgres.NewReaders(db)
	return &Handler{orderService: voraxapp.NewOrderService(voraxpostgres.NewOrderWriter(db)), readService: voraxapp.NewReadService(readers, readers)}
}

func RegisterRoutes(r chi.Router, db *database.Postgres, authService *auth.Service) {
	h := NewHandler(db)
	r.Route("/api/v1/vorax", func(vr chi.Router) {
		vr.Get("/restaurants", h.ListRestaurants)
		vr.Get("/restaurants/{restaurantID}", h.GetRestaurant)
		vr.Get("/restaurants/{restaurantID}/menu", h.ListMenu)
		vr.Group(func(pr chi.Router) {
			pr.Use(middleware.AuthRequired(authService))
			pr.Use(middleware.ExtractUserToContext)
			pr.Post("/orders", h.CreateOrder)
			pr.Get("/orders", h.ListOrders)
			pr.Get("/orders/{orderID}/tracking", h.TrackOrder)
		})
	})
}

type restaurant = voraxapp.Restaurant
type menuItem = voraxapp.MenuItem

func (h *Handler) ListRestaurants(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	items, err := h.readService.ListRestaurants(r.Context(), strings.TrimSpace(q.Get("city")), strings.TrimSpace(q.Get("cuisine")), limitFromQuery(q.Get("limit"), 20, 100))
	if err != nil {
		errorJSON(w, http.StatusInternalServerError, "could not search restaurants")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"items": items, "count": len(items)})
}
func (h *Handler) GetRestaurant(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "restaurantID"))
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid restaurant id")
		return
	}
	v, err := h.readService.GetRestaurant(r.Context(), id)
	if err != nil {
		if errors.Is(err, voraxapp.ErrResourceNotFound) {
			errorJSON(w, http.StatusNotFound, "restaurant not found")
		} else {
			errorJSON(w, http.StatusInternalServerError, "could not load restaurant")
		}
		return
	}
	jsonResponse(w, http.StatusOK, v)
}
func (h *Handler) ListMenu(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "restaurantID"))
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid restaurant id")
		return
	}
	items, err := h.readService.ListMenu(r.Context(), id)
	if err != nil {
		if errors.Is(err, voraxapp.ErrResourceNotFound) {
			errorJSON(w, http.StatusNotFound, "restaurant not found")
		} else {
			errorJSON(w, http.StatusInternalServerError, "could not load menu")
		}
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"items": items, "count": len(items)})
}

type requestedItem struct {
	MenuItemID string `json:"menu_item_id"`
	Quantity   int    `json:"quantity"`
	Notes      string `json:"notes,omitempty"`
}
type createOrderRequest struct {
	RestaurantID    string          `json:"restaurant_id"`
	DeliveryAddress string          `json:"delivery_address"`
	DeliveryLat     *float64        `json:"delivery_lat,omitempty"`
	DeliveryLng     *float64        `json:"delivery_lng,omitempty"`
	Items           []requestedItem `json:"items"`
}
type order struct {
	ID                       uuid.UUID  `json:"id"`
	UserID                   uuid.UUID  `json:"user_id"`
	RestaurantID             uuid.UUID  `json:"restaurant_id"`
	DriverID                 *uuid.UUID `json:"driver_id,omitempty"`
	DeliveryAddress          string     `json:"delivery_address"`
	Subtotal                 float64    `json:"subtotal"`
	DeliveryFee              float64    `json:"delivery_fee"`
	TotalAmount              float64    `json:"total_amount"`
	Currency                 string     `json:"currency"`
	Status                   string     `json:"status"`
	EstimatedDeliveryMinutes *int       `json:"estimated_delivery_minutes,omitempty"`
	CreatedAt                string     `json:"created_at"`
}
type pricedItem struct {
	ID        uuid.UUID
	Name      string
	Price     float64
	Currency  string
	Available bool
}

func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		errorJSON(w, http.StatusUnauthorized, "authentication required")
		return
	}
	var req createOrderRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024)).Decode(&req); err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	restaurantID, err := uuid.Parse(req.RestaurantID)
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "restaurant_id must be a UUID")
		return
	}
	if strings.TrimSpace(req.DeliveryAddress) == "" || len(req.DeliveryAddress) > 2000 {
		errorJSON(w, http.StatusBadRequest, "delivery_address is required and must be at most 2000 characters")
		return
	}
	if len(req.Items) == 0 || len(req.Items) > 50 {
		errorJSON(w, http.StatusBadRequest, "items must contain between 1 and 50 entries")
		return
	}
	if (req.DeliveryLat == nil) != (req.DeliveryLng == nil) {
		errorJSON(w, http.StatusBadRequest, "delivery_lat and delivery_lng must be supplied together")
		return
	}
	if req.DeliveryLat != nil && (*req.DeliveryLat < -90 || *req.DeliveryLat > 90 || *req.DeliveryLng < -180 || *req.DeliveryLng > 180) {
		errorJSON(w, http.StatusBadRequest, "delivery coordinates are out of range")
		return
	}
	quantities := make(map[uuid.UUID]int)
	notes := make(map[uuid.UUID]string)
	for _, it := range req.Items {
		id, e := uuid.Parse(it.MenuItemID)
		if e != nil {
			errorJSON(w, http.StatusBadRequest, "each menu_item_id must be a UUID")
			return
		}
		if it.Quantity < 1 || it.Quantity > 100 {
			errorJSON(w, http.StatusBadRequest, "item quantity must be between 1 and 100")
			return
		}
		if len(it.Notes) > 500 {
			errorJSON(w, http.StatusBadRequest, "item notes must be at most 500 characters")
			return
		}
		quantities[id] += it.Quantity
		if quantities[id] > 100 {
			errorJSON(w, http.StatusBadRequest, "combined item quantity cannot exceed 100")
			return
		}
		if notes[id] == "" {
			notes[id] = it.Notes
		}
	}
	items := make(map[uuid.UUID]voraxapp.OrderItemCommand, len(quantities))
	for id, quantity := range quantities {
		items[id] = voraxapp.OrderItemCommand{Quantity: quantity, Notes: notes[id]}
	}
	created, createErr := h.orderService.Create(r.Context(), voraxapp.CreateOrderCommand{
		UserID: userID, RestaurantID: restaurantID, DeliveryAddress: strings.TrimSpace(req.DeliveryAddress),
		DeliveryLat: req.DeliveryLat, DeliveryLng: req.DeliveryLng, Items: items,
	})
	if createErr != nil {
		switch {
		case errors.Is(createErr, voraxapp.ErrRestaurantNotFound):
			errorJSON(w, http.StatusNotFound, "restaurant not found")
		case errors.Is(createErr, voraxapp.ErrRestaurantNotAccepting):
			errorJSON(w, http.StatusConflict, "restaurant is not accepting orders")
		case errors.Is(createErr, voraxapp.ErrMenuItemsNotFound):
			errorJSON(w, http.StatusBadRequest, "one or more menu items do not belong to this restaurant")
		case errors.Is(createErr, voraxapp.ErrMenuItemsUnavailable):
			errorJSON(w, http.StatusConflict, "one or more menu items are unavailable")
		case errors.Is(createErr, voraxdomain.ErrBelowMinimum), errors.Is(createErr, voraxdomain.ErrCurrencyMismatch):
			errorJSON(w, http.StatusConflict, createErr.Error())
		default:
			errorJSON(w, http.StatusInternalServerError, "could not create order")
		}
		return
	}
	jsonResponse(w, http.StatusCreated, toHTTPOrder(created))
}

func toHTTPOrder(value voraxapp.Order) order {
	return order{ID: value.ID, UserID: value.UserID, RestaurantID: value.RestaurantID, DriverID: value.DriverID, DeliveryAddress: value.DeliveryAddress, Subtotal: value.Subtotal, DeliveryFee: value.DeliveryFee, TotalAmount: value.TotalAmount, Currency: value.Currency, Status: value.Status, EstimatedDeliveryMinutes: value.EstimatedDeliveryMinutes, CreatedAt: value.CreatedAt}
}

func (h *Handler) ListOrders(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		errorJSON(w, http.StatusUnauthorized, "authentication required")
		return
	}
	items, err := h.readService.ListOrders(r.Context(), userID, limitFromQuery(r.URL.Query().Get("limit"), 20, 100))
	if err != nil {
		errorJSON(w, http.StatusInternalServerError, "could not list orders")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"items": items, "count": len(items)})
}
func (h *Handler) TrackOrder(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		errorJSON(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "orderID"))
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid order id")
		return
	}
	result, err := h.readService.TrackOrder(r.Context(), id, userID)
	if err != nil {
		if errors.Is(err, voraxapp.ErrResourceNotFound) {
			errorJSON(w, http.StatusNotFound, "order not found")
		} else {
			errorJSON(w, http.StatusInternalServerError, "could not load order tracking")
		}
		return
	}
	jsonResponse(w, http.StatusOK, result)
}
func limitFromQuery(s string, fallback, max int) int {
	n, err := strconv.Atoi(s)
	if err != nil || n < 1 {
		return fallback
	}
	if n > max {
		return max
	}
	return n
}
func defaultJSON(b []byte, fallback string) json.RawMessage {
	if len(b) == 0 {
		return json.RawMessage(fallback)
	}
	return json.RawMessage(b)
}
func jsonResponse(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func errorJSON(w http.ResponseWriter, status int, msg string) {
	jsonResponse(w, status, map[string]string{"error": msg})
}
