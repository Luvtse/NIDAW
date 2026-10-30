package policy

import (
	"math"
	"testing"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

func TestEvaluateRejectsMissingRequiredFields(t *testing.T) {
	policy := &entities.TravelPolicy{}
	_, err := Evaluate(policy, entities.ServiceRides, map[string]interface{}{
		"fare":      12.0,
		"ride_type": "standard",
		// requested_at is deliberately missing.
	})
	if err == nil {
		t.Fatal("expected missing requested_at to fail validation")
	}
}

func TestEvaluateFoodPolicyReturnsViolation(t *testing.T) {
	restaurantID := uuid.New()
	policy := &entities.TravelPolicy{}
	policy.FoodPolicy.MaxOrderAmount = 20
	policy.FoodPolicy.BlockedRestaurants = []uuid.UUID{restaurantID}

	violations, err := Evaluate(policy, entities.ServiceFood, map[string]interface{}{
		"amount":        25.0,
		"restaurant_id": restaurantID.String(),
	})
	if err != nil {
		t.Fatalf("Evaluate returned error: %v", err)
	}
	if len(violations) != 2 {
		t.Fatalf("expected amount and blocked restaurant violations, got %v", violations)
	}
}

func TestEvaluateRejectsUnknownServiceType(t *testing.T) {
	_, err := Evaluate(&entities.TravelPolicy{}, entities.ServiceType("unknown"), map[string]interface{}{"amount": 1.0})
	if err == nil {
		t.Fatal("expected unknown service type to fail closed")
	}
}

func TestEstimatedAmountRequiresFiniteNonNegativeNumber(t *testing.T) {
	for name, value := range map[string]interface{}{
		"missing":    nil,
		"negative":   -1.0,
		"not-number": "many",
		"infinite":   math.Inf(1),
	} {
		t.Run(name, func(t *testing.T) {
			data := map[string]interface{}{}
			if value != nil {
				data["amount"] = value
			}
			if _, err := EstimatedAmount(data); err == nil {
				t.Fatalf("expected %v to be rejected", value)
			}
		})
	}
}

func TestEvaluateRidePolicyAcceptsRFC3339Timestamp(t *testing.T) {
	policy := &entities.TravelPolicy{}
	policy.RidePolicy.MaxFarePerRide = 50
	policy.RidePolicy.AllowedRideTypes = []string{"standard"}
	requestedAt := time.Date(2026, time.October, 24, 10, 0, 0, 0, time.UTC).Format(time.RFC3339)
	violations, err := Evaluate(policy, entities.ServiceRides, map[string]interface{}{
		"fare":         20.0,
		"ride_type":    "standard",
		"requested_at": requestedAt,
	})
	if err != nil {
		t.Fatalf("Evaluate returned error: %v", err)
	}
	if len(violations) != 0 {
		t.Fatalf("expected compliant ride, got violations: %v", violations)
	}
}
