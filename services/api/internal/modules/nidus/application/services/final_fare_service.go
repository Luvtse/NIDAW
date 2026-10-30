// Package services — NIDAW FARE INTEGRITY (Phase 1/2): final payable fare.
//
// FinalFareService computes the amount a rider owes from ONLY the frozen
// booking contract (the FareSnapshot quoted at request time) plus explicitly
// APPROVED additions:
//
//	F_payable = max(0, F0 + S + W - P)
//
// where F0 is the frozen quoted total, S the sum of rider-approved fixed stop
// fees, W the approved waiting charges, and P the valid promotional discount.
// Actual trip distance, actual elapsed duration, driver-reported metrics and
// route deviations are NOT inputs to this function — they may be recorded for
// operations/analytics but can never increase what the rider pays.
//
// All arithmetic happens in integer ETB santim with one documented rounding
// rule (half-up to the nearest santim at every float->santim boundary). The
// service is pure: same inputs always produce a byte-identical breakdown, so
// retries after an event-bus or payment failure settle the exact same amount.
package services

import (
	"errors"
	"math"

	"github.com/google/uuid"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

// ============================================================================
// ERRORS
// ============================================================================

var (
	// ErrFinalFareNoSnapshot: settlement attempted without a frozen booking
	// contract. Refuse loudly; never invent a price at completion time.
	ErrFinalFareNoSnapshot = errors.New("cannot finalize fare without the frozen booking snapshot")

	// ErrFinalFareCurrency guards the ETB-only invariant end to end.
	ErrFinalFareCurrency = errors.New("final fare currency must be ETB")

	// ErrNegativeApprovedAmount: an approved addition/discount carrying a
	// negative santim amount is tampering or a bug, never a credit.
	ErrNegativeApprovedAmount = errors.New("approved fare adjustments must be non-negative")
)

// ============================================================================
// INPUTS / OUTPUTS
// ============================================================================

// ApprovedStop is one rider-approved intermediate stop with its disclosed
// fixed fee and (when the server-recorded stop timer crossed the policy
// threshold) its waiting charge. Both amounts are integer santim and both
// were shown to and accepted by the rider BEFORE becoming payable — the
// finalizer refuses anything not backed by this shape.
type ApprovedStop struct {
	Seq              int   `json:"seq"`
	FixedFeeSantim   int64 `json:"fixed_fee_santim"`
	WaitingChargeSan int64 `json:"waiting_charge_santim"`
}

// TotalSantim is the stop's full contribution (fee + waiting), pre-summed for
// callers that only need the aggregate.
func (s ApprovedStop) TotalSantim() int64 { return s.FixedFeeSantim + s.WaitingChargeSan }

// FinalFareInput bundles everything the payable formula consumes. Snapshot is
// mandatory; Stops must contain ONLY rider-approved stops; DiscountSantim is
// the authoritative promotion amount (already clamped >= 0 upstream).
type FinalFareInput struct {
	Snapshot       *entities.FareSnapshot
	Stops          []ApprovedStop
	DiscountSantim int64
}

// FinalFareLine is one displayed line of the authoritative breakdown. Amounts
// are integer santim; display layers format them. Kind values are stable
// contract strings consumed by receipts and both apps.
type FinalFareLine struct {
	Kind         string `json:"kind"` // booking | stop_fee | waiting | discount
	Label        string `json:"label"`
	AmountSantim int64  `json:"amount_santim"` // signed: discounts negative
}

// FinalFareResult is the deterministic, persistable payable computation. It
// carries the complete breakdown so receipt, ledger and payment provider all
// consume the SAME numbers rather than re-deriving them independently.
type FinalFareResult struct {
	RideID uuid.UUID `json:"ride_id"`

	BookingFareSantim int64  `json:"booking_fare_santim"`    // F0 (frozen)
	StopFeesSantim    int64  `json:"stop_fees_santim"`       // S
	WaitingSantim     int64  `json:"waiting_charges_santim"` // W
	GrossFareSantim   int64  `json:"gross_fare_santim"`      // F0+S+W
	DiscountSantim    int64  `json:"promo_discount_santim"`  // P
	PayableSantim     int64  `json:"payable_fare_santim"`    // max(0, gross-P)
	Currency          string `json:"currency"`
	Lines             []FinalFareLine `json:"lines"`
	FareSnapshotID    uuid.UUID `json:"fare_snapshot_id"`
	IdempotencyKey    string    `json:"idempotency_key"`
}

// ============================================================================
// SERVICE
// ============================================================================

// FinalFareService computes payables. Stateless and side-effect free — safe
// to call concurrently and on retry; identical inputs yield identical outputs.
type FinalFareService struct{}

// NewFinalFareService constructs the service.
func NewFinalFareService() *FinalFareService { return &FinalFareService{} }

// Compute evaluates F_payable = max(0, F0 + S + W - P) in santim.
//
// Rules enforced here (and covered by final_fare_service_test.go):
//   - A missing snapshot is fatal (ErrFinalFareNoSnapshot): completion NEVER
//     reprices from actual trip metrics as a fallback.
//   - Currency must be ETB on the snapshot.
//   - Stop/waiting/discount amounts must be non-negative.
//   - The payable floor is zero: an over-large promo cannot mint a credit.
//   - Waiting charges derive from the ORIGINAL booking fare (policy computed
//     upstream in the stop module); this service simply sums approved values
//     and therefore cannot compound charges.
func (*FinalFareService) Compute(in FinalFareInput) (*FinalFareResult, error) {
	if in.Snapshot == nil {
		return nil, ErrFinalFareNoSnapshot
	}
	snap := in.Snapshot
	if err := snap.Validate(); err != nil {
		return nil, err
	}
	if snap.Currency != entities.CurrencyETB {
		return nil, ErrFinalFareCurrency
	}
	if in.DiscountSantim < 0 {
		return nil, ErrNegativeApprovedAmount
	}

	var stopFees, waiting int64
	lines := make([]FinalFareLine, 0, len(in.Stops)+4)
	lines = append(lines, FinalFareLine{
		Kind: "booking", Label: "Booking fare (frozen at confirmation)",
		AmountSantim: snap.QuotedTotalSantim,
	})
	for _, st := range in.Stops {
		if st.FixedFeeSantim < 0 || st.WaitingChargeSan < 0 {
			return nil, ErrNegativeApprovedAmount
		}
		stopFees += st.FixedFeeSantim
		waiting += st.WaitingChargeSan
		if st.FixedFeeSantim > 0 {
			lines = append(lines, FinalFareLine{
				Kind: "stop_fee", Label: stopFeeLabel(st.Seq), AmountSantim: st.FixedFeeSantim,
			})
		}
		if st.WaitingChargeSan > 0 {
			lines = append(lines, FinalFareLine{
				Kind: "waiting", Label: waitingLabel(st.Seq), AmountSantim: st.WaitingChargeSan,
			})
		}
	}

	gross := snap.QuotedTotalSantim + stopFees + waiting
	payable := gross - in.DiscountSantim
	if payable < 0 {
		payable = 0
	}
	if in.DiscountSantim > 0 {
		lines = append(lines, FinalFareLine{
			Kind: "discount", Label: "Promotion discount", AmountSantim: -in.DiscountSantim,
		})
	}

	return &FinalFareResult{
		RideID:            snap.RideID,
		BookingFareSantim: snap.QuotedTotalSantim,
		StopFeesSantim:    stopFees,
		WaitingSantim:     waiting,
		GrossFareSantim:   gross,
		DiscountSantim:    in.DiscountSantim,
		PayableSantim:     payable,
		Currency:          entities.CurrencyETB,
		Lines:             lines,
		FareSnapshotID:    snap.ID,
		IdempotencyKey:    snap.IdempotencyKey,
	}, nil
}

// SantimToMajor converts an integer santim amount to the decimal Birr view
// used by legacy NUMERIC(10,2) columns and payment gateways expecting major
// units. Exact by construction (integer / 100), formatted with half-up
// rounding guard for any future non-integer callers.
func SantimToMajor(santim int64) float64 {
	return math.Round(float64(santim)) / float64(entities.SantimPerBirr)
}

// MajorToSantim converts a major-unit amount to integer santim with the
// platform-wide deterministic rule: round HALF UP (away from zero for
// negatives) to the nearest santim. NaN/Inf inputs map to 0 rather than
// panicking — callers validating money should reject those values before
// conversion; this is defense-in-depth.
func MajorToSantim(v float64) int64 {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return 0
	}
	scaled := v * float64(entities.SantimPerBirr)
	if scaled < 0 {
		return int64(-math.Round(-scaled))
	}
	return int64(math.Round(scaled))
}

func stopFeeLabel(seq int) string {
	if seq <= 0 {
		return "Approved stop fee"
	}
	return "Approved stop fee (stop " + itoa(seq) + ")"
}

func waitingLabel(seq int) string {
	if seq <= 0 {
		return "Approved stop waiting charge"
	}
	return "Stop waiting charge (stop " + itoa(seq) + ")"
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	if neg {
		return "-" + string(b)
	}
	return string(b)
}
