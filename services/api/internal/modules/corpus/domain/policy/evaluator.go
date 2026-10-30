// Package policy contains deterministic Corpus policy evaluation rules. It has
// no database or event-bus dependencies so the rules can be tested in isolation.
package policy

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

// EstimatedAmount returns the required, non-negative amount used by Corpus
// approval and spending-limit decisions. Missing or malformed values fail
// closed instead of silently becoming zero.
func EstimatedAmount(data map[string]interface{}) (float64, error) {
	amount, err := requiredNumber(data, "amount")
	if err != nil {
		return 0, err
	}
	if amount < 0 || math.IsNaN(amount) || math.IsInf(amount, 0) {
		return 0, fmt.Errorf("booking data field %q must be a finite non-negative number", "amount")
	}
	return amount, nil
}

// Evaluate checks the service-specific fields and evaluates them against the
// selected corporate policy. Required fields are validated explicitly; an
// invalid payload is never treated as policy-compliant by default.
func Evaluate(policy *entities.TravelPolicy, serviceType entities.ServiceType, data map[string]interface{}) ([]string, error) {
	if policy == nil {
		return nil, fmt.Errorf("travel policy is required")
	}
	if data == nil {
		return nil, fmt.Errorf("booking data is required")
	}

	violations := make([]string, 0)
	switch serviceType {
	case entities.ServiceRides:
		fare, err := requiredNumber(data, "fare")
		if err != nil {
			return nil, err
		}
		rideType, err := requiredString(data, "ride_type")
		if err != nil {
			return nil, err
		}
		requestedAt, err := requiredTime(data, "requested_at")
		if err != nil {
			return nil, err
		}
		if fare < 0 {
			return nil, fmt.Errorf("booking data field %q must be non-negative", "fare")
		}
		if fare > policy.RidePolicy.MaxFarePerRide {
			violations = append(violations, "Fare exceeds maximum allowed per ride")
		}
		if !containsString(policy.RidePolicy.AllowedRideTypes, rideType) {
			violations = append(violations, "Ride type not allowed by policy")
		}
		for _, hour := range policy.RidePolicy.BlockedHours {
			if requestedAt.Hour() == hour {
				violations = append(violations, "Rides not allowed during this hour")
				break
			}
		}
		if policy.RidePolicy.WeekendRestriction && (requestedAt.Weekday() == time.Saturday || requestedAt.Weekday() == time.Sunday) {
			violations = append(violations, "Rides not allowed on weekends")
		}
	case entities.ServiceHotels:
		price, err := requiredNumber(data, "price_per_night")
		if err != nil {
			return nil, err
		}
		stars, err := requiredInteger(data, "star_rating")
		if err != nil {
			return nil, err
		}
		chain, err := requiredString(data, "chain")
		if err != nil {
			return nil, err
		}
		if price < 0 {
			return nil, fmt.Errorf("booking data field %q must be non-negative", "price_per_night")
		}
		if stars < 0 {
			return nil, fmt.Errorf("booking data field %q must be non-negative", "star_rating")
		}
		if price > policy.HotelPolicy.MaxPricePerNight {
			violations = append(violations, "Price per night exceeds policy limit")
		}
		if stars > policy.HotelPolicy.MaxStarRating {
			violations = append(violations, "Hotel star rating exceeds policy limit")
		}
		if containsString(policy.HotelPolicy.BlockedChains, chain) {
			violations = append(violations, "Hotel chain is blocked by policy")
		}
	case entities.ServiceFood:
		amount, err := requiredNumber(data, "amount")
		if err != nil {
			return nil, err
		}
		restaurantID, err := requiredUUID(data, "restaurant_id")
		if err != nil {
			return nil, err
		}
		if amount > policy.FoodPolicy.MaxOrderAmount {
			violations = append(violations, "Order amount exceeds policy limit")
		}
		for _, blocked := range policy.FoodPolicy.BlockedRestaurants {
			if blocked == restaurantID {
				violations = append(violations, "Restaurant is blocked by policy")
				break
			}
		}
	case entities.ServiceFreight:
		value, err := requiredNumber(data, "shipment_value")
		if err != nil {
			return nil, err
		}
		carrierID, err := requiredUUID(data, "carrier_id")
		if err != nil {
			return nil, err
		}
		if value < 0 {
			return nil, fmt.Errorf("booking data field %q must be non-negative", "shipment_value")
		}
		if value > policy.FreightPolicy.MaxShipmentValue {
			violations = append(violations, "Shipment value exceeds policy limit")
		}
		if len(policy.FreightPolicy.AllowedCarriers) > 0 {
			allowed := false
			for _, carrier := range policy.FreightPolicy.AllowedCarriers {
				if carrier == carrierID {
					allowed = true
					break
				}
			}
			if !allowed {
				violations = append(violations, "Carrier not in approved list")
			}
		}
	default:
		return nil, fmt.Errorf("unsupported Corpus service type %q", serviceType)
	}
	return violations, nil
}

func requiredNumber(data map[string]interface{}, key string) (float64, error) {
	value, ok := data[key]
	if !ok || value == nil {
		return 0, fmt.Errorf("booking data field %q is required", key)
	}
	var n float64
	switch v := value.(type) {
	case float64:
		n = v
	case float32:
		n = float64(v)
	case int:
		n = float64(v)
	case int32:
		n = float64(v)
	case int64:
		n = float64(v)
	case json.Number:
		parsed, err := v.Float64()
		if err != nil {
			return 0, fmt.Errorf("booking data field %q must be numeric", key)
		}
		n = parsed
	case string:
		parsed, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return 0, fmt.Errorf("booking data field %q must be numeric", key)
		}
		n = parsed
	default:
		return 0, fmt.Errorf("booking data field %q must be numeric", key)
	}
	if math.IsNaN(n) || math.IsInf(n, 0) {
		return 0, fmt.Errorf("booking data field %q must be finite", key)
	}
	return n, nil
}

func requiredInteger(data map[string]interface{}, key string) (int, error) {
	n, err := requiredNumber(data, key)
	if err != nil {
		return 0, err
	}
	if math.Trunc(n) != n || n < float64(math.MinInt) || n >= float64(math.MaxInt) {
		return 0, fmt.Errorf("booking data field %q must be an integer", key)
	}
	return int(n), nil
}

func requiredString(data map[string]interface{}, key string) (string, error) {
	value, ok := data[key]
	if !ok {
		return "", fmt.Errorf("booking data field %q is required", key)
	}
	v, ok := value.(string)
	if !ok || v == "" {
		return "", fmt.Errorf("booking data field %q must be a non-empty string", key)
	}
	return v, nil
}

func requiredUUID(data map[string]interface{}, key string) (uuid.UUID, error) {
	value, ok := data[key]
	if !ok || value == nil {
		return uuid.Nil, fmt.Errorf("booking data field %q is required", key)
	}
	switch v := value.(type) {
	case uuid.UUID:
		if v == uuid.Nil {
			return uuid.Nil, fmt.Errorf("booking data field %q must be a non-zero UUID", key)
		}
		return v, nil
	case string:
		id, err := uuid.Parse(v)
		if err != nil || id == uuid.Nil {
			return uuid.Nil, fmt.Errorf("booking data field %q must be a non-zero UUID", key)
		}
		return id, nil
	default:
		return uuid.Nil, fmt.Errorf("booking data field %q must be a UUID", key)
	}
}

func requiredTime(data map[string]interface{}, key string) (time.Time, error) {
	value, ok := data[key]
	if !ok || value == nil {
		return time.Time{}, fmt.Errorf("booking data field %q is required", key)
	}
	switch v := value.(type) {
	case time.Time:
		if v.IsZero() {
			return time.Time{}, fmt.Errorf("booking data field %q must be a valid time", key)
		}
		return v, nil
	case string:
		parsed, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return time.Time{}, fmt.Errorf("booking data field %q must be an RFC3339 timestamp", key)
		}
		return parsed, nil
	default:
		return time.Time{}, fmt.Errorf("booking data field %q must be a time or RFC3339 timestamp", key)
	}
}

func containsString(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}
