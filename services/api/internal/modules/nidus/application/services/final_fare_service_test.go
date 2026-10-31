package services

// NIDAW FARE INTEGRITY — mandatory test scenarios (Part 8) for the final
// payable fare service. Every monetary assertion is in integer ETB santim.

import (
	"math"
	"testing"
	"time"

	"github.com/google/uuid"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

// makeSnap builds a VALID frozen snapshot: base 2500 + distance 3500 + time
// 1500 = 7500 santim gross, minimum-fare floor 500 not applied. Quoted total
// defaults to the gross unless the test overrides it.
func makeSnap(t *testing.T, quoted int64) *entities.FareSnapshot {
	t.Helper()
	rideID := uuid.New()
	comp := entities.FareComponents{
		BaseFareSantim:     2500,
		DistanceFareSantim: 3500,
		TimeFareSantim:     1500,
		SurgeAmountSantim:  0,
		MinimumFareSantim:  500,
		GrossFareSantim:    7500,
		RideType:           "standard",
	}
	if quoted <= 0 {
		quoted = comp.GrossFareSantim
	}
	snap := &entities.FareSnapshot{
		ID:                   uuid.New(),
		RideID:               rideID,
		IdempotencyKey:       "finalize:" + rideID.String(),
		PickupLat:            9.0108,
		PickupLng:            38.7517,
		DropoffLat:           8.985,
		DropoffLng:           38.79,
		ContractDistanceKm:   10,
		ContractDurationMin:  30,
		Components:           comp,
		PricingConfigVersion: "v1",
		DurationRuleVersion:  DurationRuleVersionV1,
		MinutesPerKm:         3.0,
		Currency:             entities.CurrencyETB,
		QuotedTotalSantim:    quoted,
		FrozenAt:             time.Now().UTC(),
	}
	if err := snap.Validate(); err != nil {
		t.Fatalf("fixture snapshot must be valid: %v", err)
	}
	return snap
}

func TestFinalFare_BasicFormula(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)

	res, err := svc.Compute(FinalFareInput{Snapshot: snap})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.PayableSantim != 7500 || res.GrossFareSantim != 7500 {
		t.Fatalf("payable/gross = %d/%d, want 7500/7500", res.PayableSantim, res.GrossFareSantim)
	}
	if res.Currency != entities.CurrencyETB {
		t.Fatalf("currency = %q, want ETB", res.Currency)
	}
	if res.IdempotencyKey != snap.IdempotencyKey || res.FareSnapshotID != snap.ID {
		t.Fatal("result must carry the snapshot's identity for settlement tracing")
	}
}

// Scenario: a normal trip finishes with DIFFERENT actual distance/duration —
// the payable is computed exclusively from the frozen snapshot, so the
// original fare remains unchanged. Actual metrics are not even inputs here;
// this test pins that contract shape (no re-pricing API exists).
func TestFinalFare_ActualMetricsNeverReprice(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)

	first, err := svc.Compute(FinalFareInput{Snapshot: snap})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	// Simulate "driver drove 18 km in 55 minutes": nothing about the snapshot
	// or input changes, so recomputation (e.g. on settlement retry) yields
	// byte-identical numbers.
	snapActualsUntouched := *snap
	second, err := svc.Compute(FinalFareInput{Snapshot: &snapActualsUntouched})
	if err != nil {
		t.Fatalf("Compute retry: %v", err)
	}
	if first.PayableSantim != second.PayableSantim || first.GrossFareSantim != second.GrossFareSantim {
		t.Fatalf("retry changed payable: %d vs %d", first.PayableSantim, second.PayableSantim)
	}
	if len(first.Lines) != len(second.Lines) {
		t.Fatal("retry changed breakdown line count")
	}
	for i := range first.Lines {
		if first.Lines[i] != second.Lines[i] {
			t.Fatalf("line %d differs on retry: %+v vs %+v", i, first.Lines[i], second.Lines[i])
		}
	}
}

// Scenario: driver takes a longer route / reports manipulated distance and
// duration. The contractual fields inside the snapshot (10 km / 30 min) are
// what money uses; tampered ACTUAL values cannot enter Compute at all.
func TestFinalFare_ManipulatedDriverReportIsIgnored(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)
	// Even if buggy code overwrote the snapshot's contract fields, the quoted
	// TOTAL still governs the payable — completing a trip introduces no new
	// charge beyond approved additions.
	snap.ContractDistanceKm = 99
	snap.ContractDurationMin = 600
	res, err := svc.Compute(FinalFareInput{Snapshot: snap})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.PayableSantim != snap.QuotedTotalSantim {
		t.Fatalf("payable %d must equal frozen quote %d regardless of reported metrics",
			res.PayableSantim, snap.QuotedTotalSantim)
	}
}

func TestFinalFare_ApprovedStopsAndWaiting(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)

	res, err := svc.Compute(FinalFareInput{
		Snapshot: snap,
		Stops: []ApprovedStop{
			{Seq: 1, FixedFeeSantim: 300},                         // short stop: fee only
			{Seq: 2, FixedFeeSantim: 300, WaitingChargeSan: 3750}, // long stop: fee + 50% of F0
		},
	})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	wantGross := int64(7500 + 300 + 300 + 3750)
	if res.StopFeesSantim != 600 || res.WaitingSantim != 3750 {
		t.Fatalf("S/W = %d/%d, want 600/3750", res.StopFeesSantim, res.WaitingSantim)
	}
	if res.GrossFareSantim != wantGross || res.PayableSantim != wantGross {
		t.Fatalf("gross/payable = %d/%d, want %d", res.GrossFareSantim, res.PayableSantim, wantGross)
	}
	// Breakdown lines: booking + 2 fees + 1 waiting = 4.
	if len(res.Lines) != 4 {
		t.Fatalf("lines = %d, want 4 (%+v)", len(res.Lines), res.Lines)
	}
}

// Non-compounding rule: the waiting charge was computed upstream from the
// ORIGINAL booking fare only. Because Compute merely sums approved values,
// adding MORE stops can never retroactively inflate an earlier stop's waiting
// charge — verify by comparing two runs where stop 1 stands alone vs. shares
// the trip with stop 2.
func TestFinalFare_WaitingNotCompoundedByOtherStops(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)

	solo, err := svc.Compute(FinalFareInput{Snapshot: snap,
		Stops: []ApprovedStop{{Seq: 1, FixedFeeSantim: 300, WaitingChargeSan: 3750}}})
	if err != nil {
		t.Fatalf("Compute solo: %v", err)
	}
	withExtra, err := svc.Compute(FinalFareInput{Snapshot: snap,
		Stops: []ApprovedStop{
			{Seq: 1, FixedFeeSantim: 300, WaitingChargeSan: 3750},
			{Seq: 2, FixedFeeSantim: 300},
		}})
	if err != nil {
		t.Fatalf("Compute with extra: %v", err)
	}
	if withExtra.WaitingSantim != solo.WaitingSantim {
		t.Fatalf("waiting compounded: %d vs %d", withExtra.WaitingSantim, solo.WaitingSantim)
	}
	if withExtra.PayableSantim != solo.PayableSantim+300 {
		t.Fatalf("extra stop contributed %d, want exactly its fixed fee 300",
			withExtra.PayableSantim-solo.PayableSantim)
	}
}

func TestFinalFare_DiscountFloorAtZero(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)

	res, err := svc.Compute(FinalFareInput{Snapshot: snap, DiscountSantim: 2000})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.PayableSantim != 5500 {
		t.Fatalf("payable = %d, want 5500", res.PayableSantim)
	}

	// Over-large promo floors at zero — never a credit.
	res2, err := svc.Compute(FinalFareInput{Snapshot: snap, DiscountSantim: 99999})
	if err != nil {
		t.Fatalf("Compute floor: %v", err)
	}
	if res2.PayableSantim != 0 {
		t.Fatalf("floored payable = %d, want 0", res2.PayableSantim)
	}
	// Gross is untouched by discounts (commission basis stays honest).
	if res2.GrossFareSantim != 7500 {
		t.Fatalf("gross changed by discount: %d", res2.GrossFareSantim)
	}
}

func TestFinalFare_RejectsBadInputs(t *testing.T) {
	svc := NewFinalFareService()

	if _, err := svc.Compute(FinalFareInput{Snapshot: nil}); err != ErrFinalFareNoSnapshot {
		t.Fatalf("nil snapshot err = %v, want ErrFinalFareNoSnapshot", err)
	}

	badCur := makeSnap(t, 7500)
	badCur.Currency = "USD"
	if _, err := svc.Compute(FinalFareInput{Snapshot: badCur}); err == nil {
		t.Fatal("non-ETB snapshot must be rejected, not coerced")
	}

	negDisc := makeSnap(t, 7500)
	if _, err := svc.Compute(FinalFareInput{Snapshot: negDisc, DiscountSantim: -100}); err != ErrNegativeApprovedAmount {
		t.Fatalf("negative discount err = %v", err)
	}

	negStop := makeSnap(t, 7500)
	if _, err := svc.Compute(FinalFareInput{Snapshot: negStop,
		Stops: []ApprovedStop{{Seq: 1, FixedFeeSantim: -300}}}); err != ErrNegativeApprovedAmount {
		t.Fatalf("negative stop fee err = %v", err)
	}
	if _, err := svc.Compute(FinalFareInput{Snapshot: negStop,
		Stops: []ApprovedStop{{Seq: 1, WaitingChargeSan: -1}}}); err != ErrNegativeApprovedAmount {
		t.Fatalf("negative waiting charge err = %v", err)
	}
}

func TestFinalFare_DuplicateFinalizationDeterminism(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)
	in := FinalFareInput{
		Snapshot:       snap,
		Stops:          []ApprovedStop{{Seq: 1, FixedFeeSantim: 300, WaitingChargeSan: 3750}},
		DiscountSantim: 1000,
	}
	a, err := svc.Compute(in)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	for i := 0; i < 10; i++ {
		b, err := svc.Compute(in)
		if err != nil {
			t.Fatalf("replay %d: %v", i, err)
		}
		if a.PayableSantim != b.PayableSantim || a.GrossFareSantim != b.GrossFareSantim {
			t.Fatal("replay produced different payable")
		}
		if b.PayableSantim != 7500+300+3750-1000 {
			t.Fatalf("payable = %d, want %d", b.PayableSantim, 7500+300+3750-1000)
		}
	}
}

func TestSantimMajorConversions(t *testing.T) {
	cases := []struct {
		santim int64
		major  float64
	}{
		{0, 0}, {100, 1.0}, {7550, 75.50}, {-250, -2.50}, {1, 0.01},
	}
	for _, c := range cases {
		if got := SantimToMajor(c.santim); got != c.major {
			t.Errorf("SantimToMajor(%d) = %v, want %v", c.santim, got, c.major)
		}
	}
	back := []struct {
		major  float64
		santim int64
	}{
		{75.50, 7550}, {0.01, 1}, {2, 200}, {75.005, 7501}, // half-up
		{-1.235, -124}, // away-from-zero half-up
	}
	for _, c := range back {
		if got := MajorToSantim(c.major); got != c.santim {
			t.Errorf("MajorToSantim(%v) = %d, want %d", c.major, got, c.santim)
		}
	}
	if got := MajorToSantim(math.NaN()); got != 0 {
		t.Errorf("NaN must map to 0 deterministically, got %d", got)
	}
}
