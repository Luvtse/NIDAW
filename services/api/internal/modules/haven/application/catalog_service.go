// Package application coordinates Haven catalog use cases without depending on HTTP or PostgreSQL.
package application

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

// Hotel is the public catalog projection returned by Haven's discovery use cases.
type Hotel struct {
	ID            uuid.UUID
	Name          string
	Description   *string
	CountryCode   string
	City          string
	Address       *string
	Latitude      *float64
	Longitude     *float64
	StarRating    *int
	PricePerNight *float64
	Currency      string
	Amenities     []byte
	Images        []byte
}

type HotelFilter struct {
	City        string
	CountryCode string
	Limit       int
}

type HotelReader interface {
	ListHotels(context.Context, HotelFilter) ([]Hotel, error)
	GetHotel(context.Context, uuid.UUID) (Hotel, error)
}

// CatalogService exposes hotel discovery while keeping persistence behind HotelReader.
type CatalogService struct{ reader HotelReader }

func NewCatalogService(reader HotelReader) *CatalogService {
	return &CatalogService{reader: reader}
}

func (s *CatalogService) ListHotels(ctx context.Context, filter HotelFilter) ([]Hotel, error) {
	if s == nil || s.reader == nil {
		return nil, errors.New("Haven hotel catalog reader is not configured")
	}
	if filter.Limit < 1 {
		filter.Limit = 20
	}
	if filter.Limit > 100 {
		filter.Limit = 100
	}
	return s.reader.ListHotels(ctx, filter)
}

func (s *CatalogService) GetHotel(ctx context.Context, id uuid.UUID) (Hotel, error) {
	if s == nil || s.reader == nil {
		return Hotel{}, errors.New("Haven hotel catalog reader is not configured")
	}
	return s.reader.GetHotel(ctx, id)
}
