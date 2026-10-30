package commands

import (
	"errors"
	"fmt"
)

// ============================================================================
// RIDE SETTLEMENT CONTRACT (Phase 3 — one authoritative money document)
// ----------------------------------------------------------------------------
// The canonical monetary settlement contract carried by every ride.completed
// event. It is the ONLY description of ride money that the ledger, receipts,
// both apps and the payment provider are allowed to consume; nothing here is
// re-derived from actual trip metrics, driver reports or client assertions.
//
// Units: integer ETB santim (1 ETB = 100 santim). "Cents" in this package is
// the local name for santim (see valueobjects.CentsPerUnit). Floats never
// cross this boundary.
//
// Invariants enforced by Validate():
//   - Currency must be exactly ETB (reject, never coerce).
//   - Identity fields present; gross reconciles to F0 + S + W to the santim.
//   - Payable is max(0, gross - P) with P clamped into [0, gross] — an
//     over-large discount can never mint a credit for the rider.
//   - Commission is charged on GROSS (the platform funds promo discounts
//     unless a policy explicitly states otherwise), so driver earnings
//     reconcile as gross - commission regardless of the discount the rider
//     received.
//   - Tip is separately identified and NEVER folded into payable, commission
//     basis or driver fare earnings (the dedicated tip policy settles it
//     straight to the driver's available balance, idempotent per ride).
//   - SettlementID / IdempotencyKey / FareSnapshotID locate the contract so
//     retries return the same result and duplicates are acknowledged, not
//     re-charged.
// ============================================================================

// ContractCurrency is the only currency the settlement contract accepts.
const ContractCurrency = "ETB"

// ErrSettlementContractRejected signals an inbound settlement payload whose
// money cannot reconcile — the consumer must refuse it loudly (and let the
// broker retry/alert) rather than inventing amounts.
var ErrSettlementContractRejected = errors.New("ledger: settlement contract rejected")

func contractErr(format string, a ...interface{}) error {
	return fmt.Errorf("%w: %s", ErrSettlementContractRejected, fmt.Sprintf(format, a...))
}

// RideSettlementContract is the immutable money document produced at fare
// finalization and consumed verbatim at settlement. Field names mirror the
// wire keys of the ride.completed event payload emitted by the nidus
// completion command (single source of truth for both sides).
type RideSettlementContract struct {
	// ---- Identity ----------------------------------------------------------
	RideID          string `json:"ride_id"`                 // uuid text
	RiderID         string `json:"user_id"`                 // uuid text — debited account
	DriverID        string `json:"driver_id"`               // uuid text — LEDGER identity (driver's USER id)
	SettlementID    string `json:"settlement_id"`           // deterministic settlement identifier
	FareSnapshotID  string `json:"fare_snapshot_id"`        // immutable booking contract pointer
	IdempotencyKey  string `json:"idempotency_key"`         // duplicate-delivery guard
	PaymentMethod   string `json:"payment_method"`          // cash rides settle with the SAME payable amount
	PendingCashCollection bool `json:"pending_cash_collection"`
	CompletedAtUnix int64  `json:"completed_at_unix"`

	// ---- Authoritative amounts (integer ETB santim) ------------------------
	BookingFareSantim    int64  `json:"booking_fare_santim"`    // F0 frozen quote
	StopFeesSantim       int64  `json:"stop_fees_santim"`       // S rider-approved fixed stop fees
	WaitingChargesSantim int64  `json:"waiting_charges_santim"` // W server-timed waiting charges
	GrossFareSantim      int64  `json:"gross_fare_santim"`      // F0 + S + W (pre-discount)
	DiscountSantim       int64  `json:"discount_santim"`        // P valid promotional discount
	PayableSantim        int64  `json:"payable_fare_santim"`    // max(0, gross - P): rider debit
	CommissionSantim     int64  `json:"commission_santim"`      // platform fee, basis = GROSS
	DriverEarningsSantim int64  `json:"driver_earnings_santim"` // gross - commission
	TipSantim            int64  `json:"tip_santim"`             // separately identified gratuity
	Currency             string `json:"currency"`               // always ETB
}

// Validate enforces the contract invariants listed in the file header. A
// failure means the producer emitted money that cannot reconcile — settlement
// refuses loudly rather than silently picking different numbers.
func (c RideSettlementContract) Validate() error {
	if c.RideID == "" || c.RiderID == "" || c.DriverID == "" {
		return contractErr("ride, rider and driver ids are required")
	}
	if c.Currency != ContractCurrency {
		return contractErr("currency %q is not ETB (reject, never coerce)", c.Currency)
	}
	if c.BookingFareSantim < 0 || c.StopFeesSantim < 0 || c.WaitingChargesSantim < 0 {
		return contractErr("negative component amount")
	}
	if got := c.BookingFareSantim + c.StopFeesSantim + c.WaitingChargesSantim; got != c.GrossFareSantim {
		return contractErr("gross does not reconcile to F0+S+W: %d != %d santim", got, c.GrossFareSantim)
	}
	if c.DiscountSantim < 0 || c.DiscountSantim > c.GrossFareSantim {
		return contractErr("discount %d outside [0, gross %d]", c.DiscountSantim, c.GrossFareSantim)
	}
	wantPayable := c.GrossFareSantim - c.DiscountSantim
	if wantPayable < 0 {
		wantPayable = 0
	}
	if c.PayableSantim != wantPayable {
		return contractErr("payable is not max(0, gross - discount): %d != %d santim", c.PayableSantim, wantPayable)
	}
	if c.CommissionSantim < 0 || c.CommissionSantim > c.GrossFareSantim {
		return contractErr("commission %d outside [0, gross %d]", c.CommissionSantim, c.GrossFareSantim)
	}
	if c.DriverEarningsSantim != c.GrossFareSantim-c.CommissionSantim {
		return contractErr("driver earnings %d are not gross - commission (%d)",
			c.DriverEarningsSantim, c.GrossFareSantim-c.CommissionSantim)
	}
	if c.TipSantim < 0 {
		return contractErr("tip must be non-negative, got %d", c.TipSantim)
	}
	return nil
}

// ReconcileBalance exposes the four money legs of the contract: rider debit,
// driver fare credit (escrowed), platform commission and tip transfer. Tests
// and dashboards use it to prove the double-entry closes to the santim.
func (c RideSettlementContract) ReconcileBalance() (debit, driverCredit, platform, tip int64) {
	return c.PayableSantim, c.DriverEarningsSantim, c.CommissionSantim, c.TipSantim
}
