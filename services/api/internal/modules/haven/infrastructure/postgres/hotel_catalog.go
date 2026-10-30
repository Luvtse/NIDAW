// Package postgres adapts Haven's hotel catalog use cases to PostgreSQL.
package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/haven/application"
	"nidaw-backend/internal/shared/database"
)

type HotelCatalog struct{ db *database.Postgres }

func NewHotelCatalog(db *database.Postgres) *HotelCatalog { return &HotelCatalog{db: db} }

const hotelCatalogColumns = `id,name,description,country_code,city,address,latitude,longitude,star_rating,COALESCE(price_per_night,0),COALESCE(currency,'USD'),amenities,images`

func (c *HotelCatalog) ListHotels(ctx context.Context, filter application.HotelFilter) ([]application.Hotel, error) {
	rows, err := c.db.Query(ctx, `SELECT `+hotelCatalogColumns+` FROM hotels WHERE status='active' AND ($1='' OR city ILIKE '%' || $1 || '%') AND ($2='' OR country_code=$2) ORDER BY city,name LIMIT $3`, filter.City, filter.CountryCode, filter.Limit)
	if err != nil {
		return nil, fmt.Errorf("query hotel catalog: %w", err)
	}
	defer rows.Close()
	items := make([]application.Hotel, 0)
	for rows.Next() {
		h, err := scanHotel(rows)
		if err != nil {
			return nil, fmt.Errorf("scan hotel catalog row: %w", err)
		}
		items = append(items, h)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate hotel catalog: %w", err)
	}
	return items, nil
}

func (c *HotelCatalog) GetHotel(ctx context.Context, id uuid.UUID) (application.Hotel, error) {
	h, err := scanHotel(c.db.QueryRow(ctx, `SELECT `+hotelCatalogColumns+` FROM hotels WHERE id=$1 AND status='active'`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return application.Hotel{}, application.ErrHotelNotFound
		}
		return application.Hotel{}, fmt.Errorf("load hotel catalog detail: %w", err)
	}
	return h, nil
}

type rowScanner interface{ Scan(...any) error }

func scanHotel(row rowScanner) (application.Hotel, error) {
	var h application.Hotel
	if err := row.Scan(&h.ID, &h.Name, &h.Description, &h.CountryCode, &h.City, &h.Address, &h.Latitude, &h.Longitude, &h.StarRating, &h.PricePerNight, &h.Currency, &h.Amenities, &h.Images); err != nil {
		return application.Hotel{}, err
	}
	return h, nil
}
