// Package application coordinates Vorax read use cases independently of HTTP and PostgreSQL.
package application

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/google/uuid"
)

var ErrResourceNotFound = errors.New("Vorax resource not found")

type Restaurant struct {
	ID                       uuid.UUID       `json:"id"`
	Name                     string          `json:"name"`
	Description              *string         `json:"description,omitempty"`
	CuisineType              *string         `json:"cuisine_type,omitempty"`
	CountryCode              string          `json:"country_code"`
	City                     string          `json:"city"`
	Address                  *string         `json:"address,omitempty"`
	Latitude                 *float64        `json:"latitude,omitempty"`
	Longitude                *float64        `json:"longitude,omitempty"`
	Rating                   float64         `json:"rating"`
	DeliveryFee              float64         `json:"delivery_fee"`
	MinOrderAmount           float64         `json:"min_order_amount"`
	EstimatedDeliveryMinutes int             `json:"estimated_delivery_minutes"`
	Images                   json.RawMessage `json:"images"`
}

type MenuItem struct {
	ID           uuid.UUID `json:"id"`
	RestaurantID uuid.UUID `json:"restaurant_id"`
	Name         string    `json:"name"`
	Description  *string   `json:"description,omitempty"`
	Price        float64   `json:"price"`
	Currency     string    `json:"currency"`
	Category     *string   `json:"category,omitempty"`
	ImageURL     *string   `json:"image_url,omitempty"`
	IsAvailable  bool      `json:"is_available"`
}

type OrderSummary struct {
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

type OrderTracking struct {
	ID                       uuid.UUID  `json:"id"`
	Status                   string     `json:"status"`
	DriverID                 *uuid.UUID `json:"driver_id,omitempty"`
	EstimatedDeliveryMinutes *int       `json:"estimated_delivery_minutes,omitempty"`
	UpdatedAt                string     `json:"updated_at"`
}

type RestaurantReader interface {
	ListRestaurants(context.Context, string, string, int) ([]Restaurant, error)
	GetRestaurant(context.Context, uuid.UUID) (Restaurant, error)
	ListMenu(context.Context, uuid.UUID) ([]MenuItem, error)
}
type OrderReader interface {
	ListOrders(context.Context, uuid.UUID, int) ([]OrderSummary, error)
	TrackOrder(context.Context, uuid.UUID, uuid.UUID) (OrderTracking, error)
}

type ReadService struct {
	restaurants RestaurantReader
	orders      OrderReader
}

func NewReadService(restaurants RestaurantReader, orders OrderReader) *ReadService {
	return &ReadService{restaurants: restaurants, orders: orders}
}
func (s *ReadService) ListRestaurants(ctx context.Context, city, cuisine string, limit int) ([]Restaurant, error) {
	if s == nil || s.restaurants == nil {
		return nil, errors.New("Vorax restaurant reader is not configured")
	}
	return s.restaurants.ListRestaurants(ctx, city, cuisine, boundLimit(limit))
}
func (s *ReadService) GetRestaurant(ctx context.Context, id uuid.UUID) (Restaurant, error) {
	if s == nil || s.restaurants == nil {
		return Restaurant{}, errors.New("Vorax restaurant reader is not configured")
	}
	return s.restaurants.GetRestaurant(ctx, id)
}
func (s *ReadService) ListMenu(ctx context.Context, id uuid.UUID) ([]MenuItem, error) {
	if s == nil || s.restaurants == nil {
		return nil, errors.New("Vorax restaurant reader is not configured")
	}
	return s.restaurants.ListMenu(ctx, id)
}
func (s *ReadService) ListOrders(ctx context.Context, userID uuid.UUID, limit int) ([]OrderSummary, error) {
	if s == nil || s.orders == nil {
		return nil, errors.New("Vorax order reader is not configured")
	}
	return s.orders.ListOrders(ctx, userID, boundLimit(limit))
}
func (s *ReadService) TrackOrder(ctx context.Context, id, userID uuid.UUID) (OrderTracking, error) {
	if s == nil || s.orders == nil {
		return OrderTracking{}, errors.New("Vorax order reader is not configured")
	}
	return s.orders.TrackOrder(ctx, id, userID)
}
func boundLimit(limit int) int {
	if limit < 1 {
		return 20
	}
	if limit > 100 {
		return 100
	}
	return limit
}
