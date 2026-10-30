// Package postgres implements Vorax catalog and order read contracts.
package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/vorax/application"
	"nidaw-backend/internal/shared/database"
)

type Readers struct{ db *database.Postgres }

func NewReaders(db *database.Postgres) *Readers { return &Readers{db: db} }

func (r *Readers) ListRestaurants(ctx context.Context, city, cuisine string, limit int) ([]application.Restaurant, error) {
	rows, err := r.db.Query(ctx, `SELECT id,name,description,cuisine_type,country_code,city,address,latitude,longitude,COALESCE(rating,0),COALESCE(delivery_fee,0),COALESCE(min_order_amount,0),COALESCE(estimated_delivery_minutes,30),images FROM restaurants WHERE status='active' AND ($1='' OR city ILIKE '%'||$1||'%') AND ($2='' OR cuisine_type ILIKE '%'||$2||'%') ORDER BY rating DESC,name LIMIT $3`, city, cuisine, limit)
	if err != nil {
		return nil, fmt.Errorf("query restaurants: %w", err)
	}
	defer rows.Close()
	items := make([]application.Restaurant, 0)
	for rows.Next() {
		var v application.Restaurant
		var images []byte
		if err := rows.Scan(&v.ID, &v.Name, &v.Description, &v.CuisineType, &v.CountryCode, &v.City, &v.Address, &v.Latitude, &v.Longitude, &v.Rating, &v.DeliveryFee, &v.MinOrderAmount, &v.EstimatedDeliveryMinutes, &images); err != nil {
			return nil, fmt.Errorf("scan restaurant: %w", err)
		}
		v.Images = json.RawMessage(images)
		if len(v.Images) == 0 {
			v.Images = json.RawMessage(`[]`)
		}
		items = append(items, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate restaurants: %w", err)
	}
	return items, nil
}
func (r *Readers) GetRestaurant(ctx context.Context, id uuid.UUID) (application.Restaurant, error) {
	var v application.Restaurant
	var images []byte
	err := r.db.QueryRow(ctx, `SELECT id,name,description,cuisine_type,country_code,city,address,latitude,longitude,COALESCE(rating,0),COALESCE(delivery_fee,0),COALESCE(min_order_amount,0),COALESCE(estimated_delivery_minutes,30),images FROM restaurants WHERE id=$1 AND status='active'`, id).Scan(&v.ID, &v.Name, &v.Description, &v.CuisineType, &v.CountryCode, &v.City, &v.Address, &v.Latitude, &v.Longitude, &v.Rating, &v.DeliveryFee, &v.MinOrderAmount, &v.EstimatedDeliveryMinutes, &images)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, application.ErrResourceNotFound
	}
	if err != nil {
		return v, fmt.Errorf("load restaurant: %w", err)
	}
	v.Images = json.RawMessage(images)
	if len(v.Images) == 0 {
		v.Images = json.RawMessage(`[]`)
	}
	return v, nil
}
func (r *Readers) ListMenu(ctx context.Context, id uuid.UUID) ([]application.MenuItem, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM restaurants WHERE id=$1 AND status='active')`, id).Scan(&exists)
	if err != nil {
		return nil, fmt.Errorf("verify restaurant: %w", err)
	}
	if !exists {
		return nil, application.ErrResourceNotFound
	}
	rows, err := r.db.Query(ctx, `SELECT id,restaurant_id,name,description,price,COALESCE(currency,'USD'),category,image_url,COALESCE(is_available,true) FROM menu_items WHERE restaurant_id=$1 AND is_available=true ORDER BY category,name`, id)
	if err != nil {
		return nil, fmt.Errorf("query menu: %w", err)
	}
	defer rows.Close()
	items := make([]application.MenuItem, 0)
	for rows.Next() {
		var v application.MenuItem
		if err := rows.Scan(&v.ID, &v.RestaurantID, &v.Name, &v.Description, &v.Price, &v.Currency, &v.Category, &v.ImageURL, &v.IsAvailable); err != nil {
			return nil, fmt.Errorf("scan menu item: %w", err)
		}
		items = append(items, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate menu: %w", err)
	}
	return items, nil
}
func (r *Readers) ListOrders(ctx context.Context, userID uuid.UUID, limit int) ([]application.OrderSummary, error) {
	rows, err := r.db.Query(ctx, `SELECT id,user_id,restaurant_id,driver_id,delivery_address,subtotal,delivery_fee,total_amount,currency,status,estimated_delivery_minutes,created_at::text FROM orders WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("query orders: %w", err)
	}
	defer rows.Close()
	items := make([]application.OrderSummary, 0)
	for rows.Next() {
		var v application.OrderSummary
		if err := rows.Scan(&v.ID, &v.UserID, &v.RestaurantID, &v.DriverID, &v.DeliveryAddress, &v.Subtotal, &v.DeliveryFee, &v.TotalAmount, &v.Currency, &v.Status, &v.EstimatedDeliveryMinutes, &v.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan order: %w", err)
		}
		items = append(items, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate orders: %w", err)
	}
	return items, nil
}
func (r *Readers) TrackOrder(ctx context.Context, id, userID uuid.UUID) (application.OrderTracking, error) {
	var v application.OrderTracking
	err := r.db.QueryRow(ctx, `SELECT id,status,driver_id,estimated_delivery_minutes,updated_at::text FROM orders WHERE id=$1 AND user_id=$2`, id, userID).Scan(&v.ID, &v.Status, &v.DriverID, &v.EstimatedDeliveryMinutes, &v.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, application.ErrResourceNotFound
	}
	if err != nil {
		return v, fmt.Errorf("load order tracking: %w", err)
	}
	return v, nil
}
