// Package bookingdata defines the version-1, service-specific booking payload
// contracts accepted by Corpus. Extra fields are retained in Raw for forward
// compatibility, while fields used for policy decisions are strongly typed.
package bookingdata

import (
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

const SchemaVersion = 1

type Contract interface {
	ServiceType() entities.ServiceType
	SchemaVersion() int
	RawPayload() map[string]interface{}
}

type base struct{ raw map[string]interface{} }

func (b base) RawPayload() map[string]interface{} { return cloneMap(b.raw) }
func (b base) SchemaVersion() int                 { return SchemaVersion }

// RideV1 contains the fields required to evaluate ride policy. Other product
// fields remain in RawPayload so Corpus does not discard downstream data.
type RideV1 struct {
	base
	Amount      float64   `json:"amount"`
	Fare        float64   `json:"fare"`
	RideType    string    `json:"ride_type"`
	RequestedAt time.Time `json:"-"`
}

func (RideV1) ServiceType() entities.ServiceType { return entities.ServiceRides }

// HotelV1 contains the fields required to evaluate hotel policy.
type HotelV1 struct {
	base
	Amount        float64 `json:"amount"`
	PricePerNight float64 `json:"price_per_night"`
	StarRating    int     `json:"star_rating"`
	Chain         string  `json:"chain"`
}

func (HotelV1) ServiceType() entities.ServiceType { return entities.ServiceHotels }

// FoodV1 contains the fields required to evaluate food-order policy.
type FoodV1 struct {
	base
	Amount       float64   `json:"amount"`
	RestaurantID uuid.UUID `json:"restaurant_id"`
}

func (FoodV1) ServiceType() entities.ServiceType { return entities.ServiceFood }

// FreightV1 contains the fields required to evaluate freight policy.
type FreightV1 struct {
	base
	Amount        float64   `json:"amount"`
	ShipmentValue float64   `json:"shipment_value"`
	CarrierID     uuid.UUID `json:"carrier_id"`
}

func (FreightV1) ServiceType() entities.ServiceType { return entities.ServiceFreight }

func Parse(service entities.ServiceType, raw map[string]interface{}) (Contract, error) {
	if raw == nil {
		return nil, fmt.Errorf("booking data is required")
	}
	encoded, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("encode booking data: %w", err)
	}
	decode := func(target interface{}) error { return json.Unmarshal(encoded, target) }
	amount, err := requiredNonNegativeNumber(raw, "amount")
	if err != nil {
		return nil, err
	}
	_ = amount
	switch service {
	case entities.ServiceRides:
		var p struct {
			Fare        float64 `json:"fare"`
			RideType    string  `json:"ride_type"`
			RequestedAt string  `json:"requested_at"`
		}
		if err := decode(&p); err != nil {
			return nil, fmt.Errorf("invalid ride booking data: %w", err)
		}
		fare, err := requiredNonNegativeNumber(raw, "fare")
		if err != nil {
			return nil, err
		}
		if p.RideType == "" {
			return nil, fmt.Errorf("booking data field %q must be a non-empty string", "ride_type")
		}
		requestedAt, err := time.Parse(time.RFC3339, p.RequestedAt)
		if err != nil {
			return nil, fmt.Errorf("booking data field %q must be an RFC3339 timestamp", "requested_at")
		}
		return RideV1{base: base{cloneMap(raw)}, Amount: amount, Fare: fare, RideType: p.RideType, RequestedAt: requestedAt}, nil
	case entities.ServiceHotels:
		var p struct {
			PricePerNight float64 `json:"price_per_night"`
			StarRating    *int    `json:"star_rating"`
			Chain         string  `json:"chain"`
		}
		if err := decode(&p); err != nil {
			return nil, fmt.Errorf("invalid hotel booking data: %w", err)
		}
		price, err := requiredNonNegativeNumber(raw, "price_per_night")
		if err != nil {
			return nil, err
		}
		if p.StarRating == nil || *p.StarRating < 0 {
			return nil, fmt.Errorf("booking data field %q must be a non-negative integer", "star_rating")
		}
		if p.Chain == "" {
			return nil, fmt.Errorf("booking data field %q must be a non-empty string", "chain")
		}
		return HotelV1{base: base{cloneMap(raw)}, Amount: amount, PricePerNight: price, StarRating: *p.StarRating, Chain: p.Chain}, nil
	case entities.ServiceFood:
		var p struct {
			RestaurantID string `json:"restaurant_id"`
		}
		if err := decode(&p); err != nil {
			return nil, fmt.Errorf("invalid food booking data: %w", err)
		}
		id, err := uuid.Parse(p.RestaurantID)
		if err != nil || id == uuid.Nil {
			return nil, fmt.Errorf("booking data field %q must be a non-zero UUID", "restaurant_id")
		}
		return FoodV1{base: base{cloneMap(raw)}, Amount: amount, RestaurantID: id}, nil
	case entities.ServiceFreight:
		var p struct {
			ShipmentValue float64 `json:"shipment_value"`
			CarrierID     string  `json:"carrier_id"`
		}
		if err := decode(&p); err != nil {
			return nil, fmt.Errorf("invalid freight booking data: %w", err)
		}
		value, err := requiredNonNegativeNumber(raw, "shipment_value")
		if err != nil {
			return nil, err
		}
		id, err := uuid.Parse(p.CarrierID)
		if err != nil || id == uuid.Nil {
			return nil, fmt.Errorf("booking data field %q must be a non-zero UUID", "carrier_id")
		}
		return FreightV1{base: base{cloneMap(raw)}, Amount: amount, ShipmentValue: value, CarrierID: id}, nil
	default:
		return nil, fmt.Errorf("unsupported Corpus service type %q", service)
	}
}

func requiredNonNegativeNumber(raw map[string]interface{}, key string) (float64, error) {
	value, ok := raw[key]
	if !ok || value == nil {
		return 0, fmt.Errorf("booking data field %q is required", key)
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return 0, fmt.Errorf("booking data field %q must be numeric", key)
	}
	var number float64
	if err := json.Unmarshal(encoded, &number); err != nil || math.IsNaN(number) || math.IsInf(number, 0) || number < 0 {
		return 0, fmt.Errorf("booking data field %q must be a finite non-negative number", key)
	}
	return number, nil
}

func cloneMap(in map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}
