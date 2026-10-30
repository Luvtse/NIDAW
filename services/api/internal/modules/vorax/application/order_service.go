// Package application coordinates Vorax order use cases independently of HTTP and PostgreSQL.
package application

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var (
	ErrRestaurantNotFound     = errors.New("restaurant not found")
	ErrRestaurantNotAccepting = errors.New("restaurant is not accepting orders")
	ErrMenuItemsNotFound      = errors.New("one or more menu items do not belong to this restaurant")
	ErrMenuItemsUnavailable   = errors.New("one or more menu items are unavailable")
)

type OrderItemCommand struct {
	Quantity int
	Notes    string
}

type CreateOrderCommand struct {
	UserID          uuid.UUID
	RestaurantID    uuid.UUID
	DeliveryAddress string
	DeliveryLat     *float64
	DeliveryLng     *float64
	Items           map[uuid.UUID]OrderItemCommand
}

type Order struct {
	ID                       uuid.UUID
	UserID                   uuid.UUID
	RestaurantID             uuid.UUID
	DriverID                 *uuid.UUID
	DeliveryAddress          string
	Subtotal                 float64
	DeliveryFee              float64
	TotalAmount              float64
	Currency                 string
	Status                   string
	EstimatedDeliveryMinutes *int
	CreatedAt                string
}

type OrderWriter interface {
	CreateOrder(context.Context, CreateOrderCommand) (Order, error)
}

type OrderService struct{ writer OrderWriter }

func NewOrderService(writer OrderWriter) *OrderService { return &OrderService{writer: writer} }

func (s *OrderService) Create(ctx context.Context, cmd CreateOrderCommand) (Order, error) {
	if s == nil || s.writer == nil {
		return Order{}, errors.New("Vorax order writer is not configured")
	}
	if len(cmd.Items) == 0 || len(cmd.Items) > 50 {
		return Order{}, errors.New("order must contain between 1 and 50 distinct menu items")
	}
	for _, item := range cmd.Items {
		if item.Quantity < 1 || item.Quantity > 100 || len(item.Notes) > 500 {
			return Order{}, errors.New("order item quantity or notes are invalid")
		}
	}
	return s.writer.CreateOrder(ctx, cmd)
}
