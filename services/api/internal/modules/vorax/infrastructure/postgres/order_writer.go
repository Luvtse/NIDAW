// Package postgres adapts Vorax order creation to a single atomic PostgreSQL transaction.
package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/vorax/application"
	voraxdomain "nidaw-backend/internal/modules/vorax/domain"
	"nidaw-backend/internal/shared/database"
)

type OrderWriter struct{ db *database.Postgres }

func NewOrderWriter(db *database.Postgres) *OrderWriter { return &OrderWriter{db: db} }

type pricedItem struct {
	ID        uuid.UUID
	Name      string
	Price     float64
	Currency  string
	Available bool
}

func (w *OrderWriter) CreateOrder(ctx context.Context, cmd application.CreateOrderCommand) (application.Order, error) {
	var result application.Order
	tx, err := w.db.Pool().Begin(ctx)
	if err != nil {
		return result, fmt.Errorf("begin order transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var status, currency string
	var fee, minimum float64
	var eta int
	err = tx.QueryRow(ctx, `SELECT COALESCE(status,'inactive'),COALESCE(delivery_fee,0),COALESCE(min_order_amount,0),COALESCE(estimated_delivery_minutes,30) FROM restaurants WHERE id=$1 FOR UPDATE`, cmd.RestaurantID).Scan(&status, &fee, &minimum, &eta)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return result, application.ErrRestaurantNotFound
		}
		return result, fmt.Errorf("load restaurant for order: %w", err)
	}
	if status != "active" {
		return result, application.ErrRestaurantNotAccepting
	}

	ids := make([]uuid.UUID, 0, len(cmd.Items))
	for id := range cmd.Items {
		ids = append(ids, id)
	}
	rows, err := tx.Query(ctx, `SELECT id,name,price,COALESCE(currency,'USD'),COALESCE(is_available,true) FROM menu_items WHERE restaurant_id=$1 AND id=ANY($2::uuid[]) FOR UPDATE`, cmd.RestaurantID, ids)
	if err != nil {
		return result, fmt.Errorf("query menu prices: %w", err)
	}
	prices := make(map[uuid.UUID]pricedItem, len(ids))
	for rows.Next() {
		var item pricedItem
		if err := rows.Scan(&item.ID, &item.Name, &item.Price, &item.Currency, &item.Available); err != nil {
			rows.Close()
			return result, fmt.Errorf("scan menu price: %w", err)
		}
		prices[item.ID] = item
	}
	rowsErr := rows.Err()
	rows.Close()
	if rowsErr != nil {
		return result, fmt.Errorf("iterate menu prices: %w", rowsErr)
	}
	if len(prices) != len(cmd.Items) {
		return result, application.ErrMenuItemsNotFound
	}

	lines := make([]voraxdomain.PricedLine, 0, len(cmd.Items))
	for id, requested := range cmd.Items {
		item := prices[id]
		if !item.Available {
			return result, application.ErrMenuItemsUnavailable
		}
		lines = append(lines, voraxdomain.PricedLine{UnitPrice: item.Price, Quantity: requested.Quantity, Currency: item.Currency})
	}
	subtotal, total, resolvedCurrency, err := voraxdomain.CalculateTotals(lines, fee, minimum)
	if err != nil {
		return result, err
	}
	currency = resolvedCurrency
	err = tx.QueryRow(ctx, `INSERT INTO orders(user_id,restaurant_id,delivery_address,delivery_lat,delivery_lng,subtotal,delivery_fee,total_amount,currency,status,estimated_delivery_minutes) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending',$10) RETURNING id,user_id,restaurant_id,driver_id,delivery_address,subtotal,delivery_fee,total_amount,currency,status,estimated_delivery_minutes,created_at::text`, cmd.UserID, cmd.RestaurantID, cmd.DeliveryAddress, cmd.DeliveryLat, cmd.DeliveryLng, subtotal, fee, total, currency, eta).Scan(&result.ID, &result.UserID, &result.RestaurantID, &result.DriverID, &result.DeliveryAddress, &result.Subtotal, &result.DeliveryFee, &result.TotalAmount, &result.Currency, &result.Status, &result.EstimatedDeliveryMinutes, &result.CreatedAt)
	if err != nil {
		return result, fmt.Errorf("insert order: %w", err)
	}
	for id, requested := range cmd.Items {
		item := prices[id]
		if _, err := tx.Exec(ctx, `INSERT INTO order_items(order_id,menu_item_id,quantity,unit_price,total_price,notes) VALUES($1,$2,$3,$4,$5,$6)`, result.ID, id, requested.Quantity, item.Price, item.Price*float64(requested.Quantity), requested.Notes); err != nil {
			return result, fmt.Errorf("insert order item: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return result, fmt.Errorf("commit order transaction: %w", err)
	}
	return result, nil
}
