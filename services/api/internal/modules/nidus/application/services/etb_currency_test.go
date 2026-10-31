package services

// NIDAW FARE INTEGRITY — ETB-only currency invariants (Part 7/8).
//
// These tests pin the rule that the entire pricing contract path — quote ->
// frozen snapshot -> final payable -> settlement helpers — speaks exactly one
// currency (ETB) with integer santim minor units. Anything else fails closed;
// nothing is silently coerced or relabeled.

import (
	"errors"
	"testing"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

func TestETBOnly_SnapshotCurrencyGuard(t *testing.T) {
	snap := makeSnap(t, 7500)
	if err := snap.Validate(); err != nil {
		t.Fatalf("valid ETB snapshot rejected: %v", err)
	}

	for _, cur := range []string{"USD", "usd", "ET ", "", "EUR", "etb"} {
		bad := *snap
		bad.Currency = cur
		err := bad.Validate()
		if !errors.Is(err, entities.ErrFareSnapshotCurrency) {
			t.Fatalf("currency %q accepted or wrong error: %v", cur, err)
		}
	}

	// Lowercase etb must not be quietly upper-cased into validity either.
	lc := *snap
	lc.Currency = "etb"
	if lc.Validate() == nil {
		t.Fatal("lowercase 'etb' coerced into a valid snapshot")
	}
}

func TestETBOnly_FinalFareRejectsForeignCurrency(t *testing.T) {
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)
	snap.Currency = "USD"
	if _, err := svc.Compute(FinalFareInput{Snapshot: snap}); err == nil {
		t.Fatal("Compute accepted a USD snapshot")
	}
}

func TestETBOnly_ResultCarriesCanonicalCurrency(t *testing.T) {
	svc := NewFinalFareService()
	res, err := svc.Compute(FinalFareInput{Snapshot: makeSnap(t, 7500)})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.Currency != entities.CurrencyETB {
		t.Fatalf("result currency = %q, want the single canonical constant %q",
			res.Currency, entities.CurrencyETB)
	}
	if entities.CurrencyETB != "ETB" {
		t.Fatalf("canonical currency constant drifted: %q", entities.CurrencyETB)
	}
}

func TestETBOnly_MinorUnitScaleIsOneHundred(t *testing.T) {
	if entities.SantimPerBirr != 100 {
		t.Fatalf("SantimPerBirr = %d, want 100 (1 ETB = 100 santim)", entities.SantimPerBirr)
	}
	// Round-trip identity for every representable major amount at cent scale.
	for santim := int64(0); santim <= 100000; santim += 7 {
		major := SantimToMajor(santim)
		if back := MajorToSantim(major); back != santim {
			t.Fatalf("round trip broken: %d santim -> %v Birr -> %d", santim, major, back)
		}
	}
}

func TestETBOnly_MoneyFieldsAreIntegersInSantim(t *testing.T) {
	// The payable formula consumes ONLY integer santim; verify totals reconcile
	// without any float entering money math.
	svc := NewFinalFareService()
	snap := makeSnap(t, 7500)
	res, err := svc.Compute(FinalFareInput{
		Snapshot:       snap,
		Stops:          []ApprovedStop{{Seq: 1, FixedFeeSantim: 301, WaitingChargeSan: 3751}},
		DiscountSantim: 99,
	})
	if err != nil {
		t.Fatalf("Compute: %v", err)
	}
	if res.GrossFareSantim != 7500+301+3751 {
		t.Fatalf("gross = %d, want %d", res.GrossFareSantim, 7500+301+3751)
	}
	if res.PayableSantim != res.GrossFareSantim-99 {
		t.Fatalf("payable/gross/discount inconsistent: %d/%d/%d",
			res.PayableSantim, res.GrossFareSantim, res.DiscountSantim)
	}
	// Signed discount line keeps the ledger reconciliation exact:
	// payable == sum(lines).
	var sum int64
	for _, l := range res.Lines {
		sum += l.AmountSantim
	}
	if sum != res.PayableSantim {
		t.Fatalf("breakdown lines sum to %d, payable is %d", sum, res.PayableSantim)
	}
}
