package services

// NIDAW FARE INTEGRITY — mandatory test scenarios (Part 8) for the fixed
// contractual minutes-per-kilometre duration rule.

import (
	"errors"
	"math"
	"testing"
)

func TestContractualDuration_V1TenKmIsThirtyMinutes(t *testing.T) {
	// The canonical example from the policy: 3 min/km * 10 km = 30 minutes.
	mins, rule, err := ContractualDuration(10, DurationRuleVersionV1)
	if err != nil {
		t.Fatalf("ContractualDuration: %v", err)
	}
	if mins != 30 {
		t.Fatalf("duration = %d min, want 30", mins)
	}
	if rule.Version != DurationRuleVersionV1 || rule.MinutesPerKm != 3.0 {
		t.Fatalf("rule = %+v, want v1 @ 3.0 min/km", rule)
	}
}

func TestContractualDuration_CeilingAndFloor(t *testing.T) {
	cases := []struct {
		name string
		dist float64
		want int
	}{
		{"exact integer product", 5, 15},
		{"fractional rounds up", 3.5, 11}, // 10.5 -> ceil 11
		{"tiny distance floors at 1", 0.01, 1},
		{"zero distance floors at 1", 0, 1},
		{"long trip", 42.75, 129}, // 128.25 -> ceil 129
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, _, err := ContractualDuration(c.dist, "")
			if err != nil {
				t.Fatalf("err = %v", err)
			}
			if got != c.want {
				t.Fatalf("Tc(%v) = %d, want %d", c.dist, got, c.want)
			}
		})
	}
}

func TestContractualDuration_EmptyVersionDefaultsToV1(t *testing.T) {
	a, ra, err := ContractualDuration(10, "")
	b, rb, err2 := ContractualDuration(10, DurationRuleVersionV1)
	if err != nil || err2 != nil {
		t.Fatalf("errs: %v / %v", err, err2)
	}
	if a != b || ra != rb {
		t.Fatal("default version must equal explicit v1")
	}
	if DefaultDurationRuleVersion != DurationRuleVersionV1 {
		t.Fatalf("default version = %q, want v1", DefaultDurationRuleVersion)
	}
}

func TestContractualDuration_RejectsInvalidDistance(t *testing.T) {
	bad := []float64{-1, -0.001, math.NaN(), math.Inf(1), math.Inf(-1)}
	for _, d := range bad {
		if _, _, err := ContractualDuration(d, DurationRuleVersionV1); !errors.Is(err, ErrInvalidContractDistance) {
			t.Fatalf("distance %v err = %v, want ErrInvalidContractDistance", d, err)
		}
	}
}

func TestContractualDuration_UnknownVersionFailsClosed(t *testing.T) {
	_, _, err := ContractualDuration(10, "v2-does-not-exist")
	if !errors.Is(err, ErrUnknownDurationRule) {
		t.Fatalf("err = %v, want ErrUnknownDurationRule", err)
	}
	if _, err := LookupDurationRule("nope"); !errors.Is(err, ErrUnknownDurationRule) {
		t.Fatalf("LookupDurationRule err = %v", err)
	}
}

func TestContractualDuration_RideTypeExtensionPointMatchesFlatRule(t *testing.T) {
	// v1 is flat across ride types; the typed entry point must agree exactly.
	for _, rt := range []RideType{RideTypeStandard, RideTypePremium, RideTypeElectric, RideTypeShared, RideTypeWheelchair} {
		m1, _, err := ContractualDurationForRideType(7.3, DurationRuleVersionV1, rt)
		if err != nil {
			t.Fatalf("%s: %v", rt, err)
		}
		m2, _, err := ContractualDuration(7.3, DurationRuleVersionV1)
		if err != nil {
			t.Fatalf("base: %v", err)
		}
		if m1 != m2 {
			t.Fatalf("%s: %d != %d", rt, m1, m2)
		}
	}
}

func TestDurationRule_MonetaryRateIsNotADurationMultiplier(t *testing.T) {
	// Regression guard for the Part 2.3 warning: the ETB per-MINUTE monetary
	// rate must never be reused as the minutes-per-KM rule. The registry's
	// MinutesPerKm is a duration constant; verify the v1 rule value is 3.0
	// regardless of any pricing config loaded into the environment.
	rule, err := LookupDurationRule(DurationRuleVersionV1)
	if err != nil {
		t.Fatalf("lookup: %v", err)
	}
	if rule.MinutesPerKm != 3.0 {
		t.Fatalf("v1 MinutesPerKm mutated to %v — frozen rules are immutable", rule.MinutesPerKm)
	}
}

func TestFormatDurationMinutes(t *testing.T) {
	if got := FormatDurationMinutes(30); got != "30 min" {
		t.Fatalf("got %q", got)
	}
	if got := FormatDurationMinutes(95); got != "1h 35m" {
		t.Fatalf("got %q", got)
	}
}
