// ride_settlement_contract_test.go — Phase 3: verify that rider debit,
// platform commission, driver earnings, tips and promo discounts reconcile
// exactly to the santim on the canonical settlement contract, and that
// malformed money is rejected rather than silently settled.
package commands

import (
	"errors"
	"testing"

	"github.com/google/uuid"
)

// baseContract returns a valid contract: F0=250.00 ETB gross, 10% commission,
// no stops/tips/discount unless a test overrides fields.
func baseContract() RideSettlementContract {
	gross := int64(25_000)  // 250.00 ETB
	fee := gross * 10 / 100 // 25.00 ETB commission (basis = GROSS)
	return RideSettlementContract{
		RideID:               uuid.New().String(),
		RiderID:              uuid.New().String(),
		DriverID:             uuid.New().String(),
		SettlementID:         uuid.New().String(),
		FareSnapshotID:       uuid.New().String(),
		IdempotencyKey:       "final-fare:" + uuid.New().String(),
		PaymentMethod:        "wallet",
		BookingFareSantim:    gross,
		GrossFareSantim:      gross,
		PayableSantim:        gross,
		CommissionSantim:     fee,
		DriverEarningsSantim: gross - fee,
		Currency:             ContractCurrency,
	}
}

func validContract() RideSettlementContract {
	return baseContract()
}

func TestSettlementContract_ValidReconciles(t *testing.T) {
	c := validContract()
	if err := c.Validate(); err != nil {
		t.Fatalf("valid contract rejected: %v", err)
	}
	debit, driverCredit, platform, tip := c.ReconcileBalance()
	if debit != 25_000 || platform != 2_500 || driverCredit != 22_500 || tip != 0 {
		t.Fatalf("legs mismatch: %d %d %d %d", debit, driverCredit, platform, tip)
	}
	// Double-entry closes: rider payable + platform-funded discount == gross;
	// driver credit + commission == gross.
	if driverCredit+platform != c.GrossFareSantim {
		t.Fatal("driver legs do not sum to gross")
	}
}

func TestSettlementContract_PromoDiscountFunding(t *testing.T) {
	// §2.6: a platform-funded discount lowers the RIDER debit only. Driver
	// earnings and the commission basis stay on GROSS.
	c := validContract()
	c.DiscountSantim = 5_00 // 5.00 ETB
	c.PayableSantim = c.GrossFareSantim - c.DiscountSantim
	if err := c.Validate(); err != nil {
		t.Fatalf("discounted contract rejected: %v", err)
	}
	debit, driverCredit, platform, _ := c.ReconcileBalance()
	if debit != 24_500 {
		t.Fatalf("rider must be debited the payable (gross-discount), got %d", debit)
	}
	if platform != 2_500 || driverCredit != 22_500 {
		t.Fatalf("discount must not reduce commission or driver earnings: %d/%d", platform, driverCredit)
	}
	// The funding gap is exactly the platform's promo cost, to the santim.
	if gap := c.GrossFareSantim - debit; gap != c.DiscountSantim {
		t.Fatalf("funding gap %d != discount %d", gap, c.DiscountSantim)
	}
}

func TestSettlementContract_StopAndWaitingAdditions(t *testing.T) {
	// Gross = F0 + S + W; waiting charge computed from F0 only (non-compounding).
	c := validContract()
	c.BookingFareSantim = 20_000
	c.StopFeesSantim = 2_000
	c.WaitingChargesSantim = 10_00 // 50% of F0 = 10.00 ETB
	c.GrossFareSantim = 23_000
	c.PayableSantim = 23_000
	c.CommissionSantim = 2_300
	c.DriverEarningsSantim = 20_700
	if err := c.Validate(); err != nil {
		t.Fatalf("stop-augmented contract rejected: %v", err)
	}
}

func TestSettlementContract_Rejections(t *testing.T) {
	tests := []struct {
		name string
		mut  func(*RideSettlementContract)
	}{
		{"usd currency", func(c *RideSettlementContract) { c.Currency = "USD" }},
		{"empty currency", func(c *RideSettlementContract) { c.Currency = "" }},
		{"missing ride id", func(c *RideSettlementContract) { c.RideID = "" }},
		{"negative stop fee", func(c *RideSettlementContract) { c.StopFeesSantim = -1 }},
		{"gross does not reconcile", func(c *RideSettlementContract) { c.GrossFareSantim++ }},
		{"discount exceeds gross", func(c *RideSettlementContract) {
			c.DiscountSantim = c.GrossFareSantim + 1
			c.PayableSantim = 0
		}},
		{"payable not max(0,gross-P)", func(c *RideSettlementContract) { c.PayableSantim = c.GrossFareSantim - 1 }},
		{"commission above gross", func(c *RideSettlementContract) {
			c.CommissionSantim = c.GrossFareSantim + 1
			c.DriverEarningsSantim = 0
		}},
		{"earnings not gross-commission", func(c *RideSettlementContract) { c.DriverEarningsSantim += 5 }},
		{"negative tip", func(c *RideSettlementContract) { c.TipSantim = -1 }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c := validContract()
			tc.mut(&c)
			err := c.Validate()
			if !errors.Is(err, ErrSettlementContractRejected) {
				t.Fatalf("expected ErrSettlementContractRejected, got %v", err)
			}
		})
	}
}

func TestSettlementContract_FullDiscountClampsPayableToZero(t *testing.T) {
	c := validContract()
	c.DiscountSantim = c.GrossFareSantim
	c.PayableSantim = 0
	if err := c.Validate(); err != nil {
		t.Fatalf("100%% discount contract rejected: %v", err)
	}
	debit, driverCredit, platform, _ := c.ReconcileBalance()
	if debit != 0 {
		t.Fatalf("free ride must debit 0, got %d", debit)
	}
	// Platform still funds the ride economics on gross: driver unaffected.
	if driverCredit+platform != c.GrossFareSantim {
		t.Fatal("driver legs must still sum to gross under full discount")
	}
}

func TestSettlementContract_TipNeverEntersFareLegs(t *testing.T) {
	c := validContract()
	c.TipSantim = 50_00 // 500.00 ETB gratuity
	if err := c.Validate(); err != nil {
		t.Fatalf("tipped contract rejected: %v", err)
	}
	debit, driverCredit, platform, tip := c.ReconcileBalance()
	if tip != 50_00 {
		t.Fatalf("tip leg wrong: %d", tip)
	}
	// Tip must NOT change payable, commission basis or fare earnings.
	if debit != 25_000 || platform != 2_500 || driverCredit != 22_500 {
		t.Fatalf("tip leaked into fare legs: %d/%d/%d", debit, platform, driverCredit)
	}
}

// ----------------------------------------------------------------------------
// ProcessRidePayment settlement-leg resolution (contract vs legacy producer)
// ----------------------------------------------------------------------------

func TestSettlementLegs_ContractPath(t *testing.T) {
	c := validContract()
	c.DiscountSantim = 5_00
	c.PayableSantim = c.GrossFareSantim - c.DiscountSantim
	c.TipSantim = 1_00
	ev := RideCompletedEvent{
		RideID:   uuid.MustParse(c.RideID),
		RiderID:  uuid.MustParse(c.RiderID),
		DriverID: uuid.MustParse(c.DriverID),
		Contract: &c,
	}
	debit, commission, credit, tip, currency, err := ev.SettlementLegs()
	if err != nil {
		t.Fatalf("settlementLegs: %v", err)
	}
	if debit != 24_500 || commission != 2_500 || credit != 22_500 || tip != 1_00 {
		t.Fatalf("legs = %d/%d/%d/%d, want 24500/2500/22500/100", debit, commission, credit, tip)
	}
	if currency != ContractCurrency {
		t.Fatalf("currency %q", currency)
	}
}

func TestSettlementLegs_LegacyPath(t *testing.T) {
	ev := RideCompletedEvent{
		RideID:    uuid.New(),
		RiderID:   uuid.New(),
		DriverID:  uuid.New(),
		FareCents: 25_00,
		FeeCents:  2_50,
	}
	debit, commission, credit, tip, _, err := ev.SettlementLegs()
	if err != nil {
		t.Fatalf("legacy legs: %v", err)
	}
	if debit != 25_00 || commission != 2_50 || credit != 22_50 || tip != 0 {
		t.Fatalf("legacy legs = %d/%d/%d/%d", debit, commission, credit, tip)
	}
}

func TestSettlementLegs_RejectsInvalid(t *testing.T) {
	// Contract with tampered payable => loud rejection, never a silent fix.
	c := validContract()
	c.PayableSantim = 1 // != gross - discount
	ev := RideCompletedEvent{RideID: uuid.New(), RiderID: uuid.New(), DriverID: uuid.New(), Contract: &c}
	if _, _, _, _, _, err := ev.SettlementLegs(); !errors.Is(err, ErrSettlementContractRejected) {
		t.Fatalf("expected contract rejection, got %v", err)
	}
	// Legacy zero fare.
	ev2 := RideCompletedEvent{RideID: uuid.New(), RiderID: uuid.New(), DriverID: uuid.New()}
	if _, _, _, _, _, err := ev2.SettlementLegs(); err == nil {
		t.Fatal("zero legacy fare must be rejected")
	}
	// Legacy fee above fare.
	ev3 := RideCompletedEvent{RideID: uuid.New(), RiderID: uuid.New(), DriverID: uuid.New(), FareCents: 100, FeeCents: 101}
	if _, _, _, _, _, err := ev3.SettlementLegs(); err == nil {
		t.Fatal("fee > fare must be rejected")
	}
	// USD-labeled event is rejected, never coerced to ETB.
	usd := validContract()
	usd.Currency = "USD"
	ev4 := RideCompletedEvent{RideID: uuid.New(), RiderID: uuid.New(), DriverID: uuid.New(), Contract: &usd}
	if _, _, _, _, _, err := ev4.SettlementLegs(); !errors.Is(err, ErrSettlementContractRejected) {
		t.Fatalf("USD contract must be rejected, got %v", err)
	}
}
