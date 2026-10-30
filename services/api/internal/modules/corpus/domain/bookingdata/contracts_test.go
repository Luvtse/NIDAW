package bookingdata

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/domain/entities"
)

func TestParseReturnsTypedRideContractAndPreservesExtraFields(t *testing.T) {
	raw := map[string]interface{}{"amount": 20.0, "fare": 20.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z", "pickup": "HQ"}
	got, err := Parse(entities.ServiceRides, raw)
	if err != nil {
		t.Fatal(err)
	}
	ride, ok := got.(RideV1)
	if !ok {
		t.Fatalf("got %T, want RideV1", got)
	}
	if ride.SchemaVersion() != 1 || ride.ServiceType() != entities.ServiceRides {
		t.Fatalf("unexpected contract metadata: %+v", ride)
	}
	if ride.RequestedAt.Format(time.RFC3339) != "2026-10-24T10:00:00Z" {
		t.Fatalf("unexpected time: %s", ride.RequestedAt)
	}
	if ride.RawPayload()["pickup"] != "HQ" {
		t.Fatal("extra downstream field was not preserved")
	}
}

func TestParseRejectsMissingOrInvalidPolicyFields(t *testing.T) {
	cases := []struct {
		name    string
		service entities.ServiceType
		payload map[string]interface{}
	}{
		{"missing amount", entities.ServiceRides, map[string]interface{}{"fare": 2.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z"}},
		{"negative fare", entities.ServiceRides, map[string]interface{}{"amount": 2.0, "fare": -1.0, "ride_type": "standard", "requested_at": "2026-10-24T10:00:00Z"}},
		{"invalid time", entities.ServiceRides, map[string]interface{}{"amount": 2.0, "fare": 2.0, "ride_type": "standard", "requested_at": "yesterday"}},
		{"invalid restaurant", entities.ServiceFood, map[string]interface{}{"amount": 2.0, "restaurant_id": "not-a-uuid"}},
		{"invalid carrier", entities.ServiceFreight, map[string]interface{}{"amount": 2.0, "shipment_value": 2.0, "carrier_id": uuid.Nil.String()}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := Parse(tc.service, tc.payload); err == nil {
				t.Fatal("expected invalid payload to be rejected")
			}
		})
	}
}

func TestParseRejectsUnsupportedService(t *testing.T) {
	if _, err := Parse("other", map[string]interface{}{"amount": 1}); err == nil {
		t.Fatal("expected unsupported service error")
	}
}
