// eventbus_settlement_contract_test.go — Phase 3 (settlement integrity):
// the inbound ride.completed consumer must decode the authoritative integer
// ETB santim settlement contract emitted by the nidus completion command,
// validate it to the santim, and hand ProcessRidePayment the PAYABLE amount
// (promo discount propagated), contract commission/earnings and separately
// identified tip — never silently re-deriving money from floats or picking a
// different number when producer fields disagree.
package adapters

import (
	"errors"
	"testing"

	"github.com/google/uuid"

	"nidaw-backend/internal/modules/ledger/application/commands"
)

func contractPayload() map[string]interface{} {
	ride := uuid.New()
	rider := uuid.New()
	driver := uuid.New()
	snap := uuid.New()
	return map[string]interface{}{
		"ride_id":           ride.String(),
		"user_id":           rider.String(),
		"driver_id":         driver.String(),
		"currency":          "ETB",
		"completed_at_unix": int64(1_760_000_000),
		// Display floats consistent with the santim contract below.
		"final_fare":   250.00, // gross F0+S+W
		"platform_fee": 25.00,  // commission on GROSS
		// ---- Authoritative santim legs (what the ledger MUST consume) ------
		"booking_fare_santim":     int64(230_00), // F0 = 230.00 ETB
		"stop_fees_santim":        int64(10_00),  // S = 10.00 ETB
		"waiting_charges_santim":  int64(10_00),  // W = 10.00 ETB
		"gross_fare_santim":       int64(250_00),
		"discount_santim":         int64(25_00), // P = 25.00 ETB promo
		"payable_fare_santim":     int64(225_00),
		"commission_santim":       int64(25_00),
		"driver_earnings_santim":  int64(225_00),
		"tip_santim":              int64(5_00),
		"fare_snapshot_id":        snap.String(),
		"settlement_idempotency":  "final-fare:" + ride.String(),
		"payment_method_type":     "cash",
		"pending_cash_collection": true,
	}
}

func TestDecodePayload_ConsumesAuthoritativeSantimContract(t *testing.T) {
	in := contractPayload()
	ev, err := decodePayload(in)
	if err != nil {
		t.Fatalf("decodePayload: %v", err)
	}
	if ev.Contract == nil {
		t.Fatal("expected settlement contract to be decoded")
	}
	c := ev.Contract
	if c.PayableSantim != 225_00 || c.DiscountSantim != 25_00 {
		t.Fatalf("discount/payable not propagated: payable=%d discount=%d", c.PayableSantim, c.DiscountSantim)
	}
	if c.CommissionSantim != 25_00 || c.DriverEarningsSantim != 225_00 {
		t.Fatalf("commission/earnings mismatch: %d/%d", c.CommissionSantim, c.DriverEarningsSantim)
	}
	if c.TipSantim != 5_00 {
		t.Fatalf("tip not separately carried: %d", c.TipSantim)
	}
	if c.Currency != "ETB" {
		t.Fatalf("currency %q", c.Currency)
	}
	if c.FareSnapshotID != in["fare_snapshot_id"] || c.IdempotencyKey != in["settlement_idempotency"] {
		t.Fatal("contract identity fields lost in decode")
	}
	if !c.PendingCashCollection {
		t.Fatal("cash deferral flag lost")
	}
	// Legacy mirror fields must expose the PAYABLE (post-discount), never the
	// gross — this is exactly the Phase 3 defect being closed.
	if ev.FareCents != 225_00 {
		t.Fatalf("FareCents must mirror payable 22500, got %d", ev.FareCents)
	}
	if ev.FeeCents != 25_00 {
		t.Fatalf("FeeCents must mirror commission, got %d", ev.FeeCents)
	}
	// The legs ProcessRidePayment will settle: rider debited 225.00 (not
	// 250.00), driver held credit 225.00 (gross - commission, discount does
	// not reduce driver earnings), tip 5.00 recorded but moved elsewhere.
	debit, commission, credit, tip, currency, err := ev.SettlementLegs()
	if err != nil {
		t.Fatalf("settlementLegs: %v", err)
	}
	if debit != 225_00 || commission != 25_00 || credit != 225_00 || tip != 5_00 || currency != "ETB" {
		t.Fatalf("legs = %d/%d/%d/%d/%s", debit, commission, credit, tip, currency)
	}
}

func TestDecodePayload_LegacyFloatFallbackUnchanged(t *testing.T) {
	ride, rider, driver := uuid.New(), uuid.New(), uuid.New()
	ev, err := decodePayload(map[string]interface{}{
		"ride_id":      ride.String(),
		"user_id":      rider.String(),
		"driver_id":    driver.String(),
		"final_fare":   25.00,
		"platform_fee": 2.50,
	})
	if err != nil {
		t.Fatalf("legacy decode: %v", err)
	}
	if ev.Contract != nil {
		t.Fatal("legacy payload must not fabricate a contract")
	}
	if ev.FareCents != 2_500 || ev.FeeCents != 250 {
		// final_fare 25.00 -> 2500 cents; platform_fee 2.50 -> 250 cents.
		t.Fatalf("legacy cents = %d/%d, want 2500/250", ev.FareCents, ev.FeeCents)
	}
	if ev.Currency != "ETB" {
		t.Fatalf("legacy default currency %q", ev.Currency)
	}
}

func TestDecodePayload_RejectsNonETBCurrency(t *testing.T) {
	in := contractPayload()
	in["currency"] = "USD"
	if _, err := decodePayload(in); !errors.Is(err, commands.ErrSettlementContractRejected) {
		t.Fatalf("USD settlement must be rejected, got %v", err)
	}
}

func TestDecodePayload_RejectsUnreconciledContract(t *testing.T) {
	// Producer emits payable that is NOT max(0, gross - discount): refuse the
	// event loudly so the broker retries/alerts instead of settling invented
	// money.
	in := contractPayload()
	in["payable_fare_santim"] = int64(999_99)
	if _, err := decodePayload(in); !errors.Is(err, commands.ErrSettlementContractRejected) {
		t.Fatalf("tampered payable must be rejected, got %v", err)
	}

	// Float display field disagrees with the santim contract: no silent winner.
	in2 := contractPayload()
	in2["final_fare"] = 999.00
	if _, err := decodePayload(in2); !errors.Is(err, commands.ErrSettlementContractRejected) {
		t.Fatalf("float/santim mismatch must be rejected, got %v", err)
	}

	// Gross that does not equal F0+S+W.
	in3 := contractPayload()
	in3["gross_fare_santim"] = int64(250_01)
	in3["final_fare"] = 250.01
	if _, err := decodePayload(in3); !errors.Is(err, commands.ErrSettlementContractRejected) {
		t.Fatalf("unreconciled gross must be rejected, got %v", err)
	}
}

func TestDecodePayload_RejectsInvalidIdentityAndFare(t *testing.T) {
	if _, err := decodePayload(map[string]interface{}{
		"ride_id": "not-a-uuid", "user_id": uuid.New().String(), "driver_id": uuid.New().String(),
		"final_fare": 25.0,
	}); err == nil {
		t.Fatal("invalid ride_id must fail decode")
	}
	// Legacy zero fare remains invalid.
	if _, err := decodePayload(map[string]interface{}{
		"ride_id": uuid.New().String(), "user_id": uuid.New().String(), "driver_id": uuid.New().String(),
		"final_fare": 0,
	}); err == nil {
		t.Fatal("zero legacy fare must fail decode")
	}
}
