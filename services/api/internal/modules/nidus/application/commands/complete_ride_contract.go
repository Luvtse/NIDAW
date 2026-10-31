// Package commands — NIDAW FARE INTEGRITY (Phase 1/3): the validated
// completion-and-finalization contract shared by the application layer.
//
// CompleteRideContract is the single authoritative record of WHY a ride may
// settle and AGAINST WHAT it settles:
//
//   - Authorization: only the driver actually assigned to the ride (resolved
//     from the authenticated JWT user id) may complete it. The rider-facing
//     surfaces never submit money values; nothing on this struct can be used
//     to raise the payable amount.
//   - Contract: settlement happens exclusively against the frozen booking
//     FareSnapshot plus rider-APPROVED stop additions (§2.4/§2.5). Actual GPS
//     distance, elapsed time and driver-reported metrics are operations-only
//     inputs recorded on the ride row — they are deliberately NOT fields of
//     this contract and cannot reach the money math.
//   - Exactly-once: the contract carries the deterministic settlement
//     identity (event id = ride id in the durable outbox, ledger idempotency
//     key "ride:debit:<ride_id>", snapshot idempotency key on the payload),
//     so concurrent or replayed completions resolve to one settlement.
//
// Validate() is fail-closed: every precondition that CompleteRideHandler
// historically enforced inline (ownership, status machine, ETB currency,
// fare/snapshot reconciliation, non-negative approved additions) is checked
// here once, in one place, so HTTP handlers, workers and tests share the same
// rules instead of each re-implementing a subset.
package commands

import (
	"errors"
	"fmt"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/modules/nidus/domain/entities"

	"github.com/google/uuid"
)

// ============================================================================
// CONTRACT ERRORS
// ============================================================================

var (
	// ErrCompletionUnauthorized: the requesting driver identity does not own
	// the assignment on this ride. Mapped to HTTP 403 by the handler layer.
	ErrCompletionUnauthorized = errors.New("only the assigned driver may complete this ride")

	// ErrCompletionStateInvalid: the ride is not in a state that can legally
	// transition to completed (e.g. still searching, already terminal).
	ErrCompletionStateInvalid = entities.ErrInvalidStatusTransition

	// ErrCompletionMissingContract: no frozen fare snapshot exists for the
	// ride. Completion refuses rather than inventing a price at receipt time.
	ErrCompletionMissingContract = errors.New("ride has no frozen fare snapshot; refusing to complete without a contract")

	// ErrCompletionCurrency: the contract or ride carries a currency other
	// than ETB. Rejected loudly — never coerced or relabeled (§3 ETB-only).
	ErrCompletionCurrency = errors.New("completion contract currency must be ETB")

	// ErrCompletionFareDrift: rides.fare_amount no longer reconciles with the
	// frozen quoted total to the santim. Someone rewrote one side; settlement
	// refuses rather than picking a winner.
	ErrCompletionFareDrift = errors.New("ride fare does not match the frozen booking quote")

	// ErrCompletionNegativeAddition: an approved addition (stop fee, waiting
	// charge) or discount carrying a negative santim amount is tampering or a
	// bug, never a credit.
	ErrCompletionNegativeAddition = errors.New("approved completion additions must be non-negative")
)

// ============================================================================
// CONTRACT
// ============================================================================

// CompleteRideContract is the validated completion request assembled by
// CompleteRideHandler from trusted server-side state. Clients contribute ONLY
// the ride id and (operations-only) actual trip metrics; every monetary field
// below is loaded from the database and re-derived deterministically from the
// immutable snapshot, so a malicious or buggy client cannot influence them.
type CompleteRideContract struct {
	// Identity & authorization -------------------------------------------
	RideID        uuid.UUID // target ride
	DriverUserID  uuid.UUID // authenticated subject (user id owning the driver row)
	DriverProfile uuid.UUID // resolved drivers.id — MUST equal rides.driver_id
	RiderUserID   uuid.UUID // payer identity (rides.user_id), carried for the settlement event

	// State machine --------------------------------------------------------
	Status entities.RideStatus // must be in_progress at validation time

	// Frozen contract ------------------------------------------------------
	Snapshot *entities.FareSnapshot // immutable booking pricing contract (required)

	// Approved additions (§2.4/§2.5) — ONLY rider-approved stops belong here.
	ApprovedStops []services.ApprovedStop

	// Promotion ------------------------------------------------------------
	PromoCode      string
	DiscountSantim int64 // authoritative applied discount, clamped >= 0 upstream

	// Payment shape ---------------------------------------------------------
	IsCash   bool // cash rides defer ledger settlement to collection confirmation
	Currency string

	// Idempotency -----------------------------------------------------------
	// SettlementEventID is the deterministic outbox key (the ride UUID): one
	// settlement per ride, ever — duplicate/retried completion attempts reuse
	// the same key and cannot double-charge the rider or double-credit the
	// driver. SnapshotKey mirrors the frozen contract's idempotency key so
	// consumers can correlate payable -> contract -> ledger entry.
	SettlementEventID uuid.UUID
	SnapshotKey       string
}

// NewCompleteRideContract assembles the contract from the handler's trusted
// inputs. It performs NO I/O; all persistence reads happen before this call.
func NewCompleteRideContract(ride *entities.Ride, snapshot *entities.FareSnapshot,
	driverProfile uuid.UUID, driverUserID uuid.UUID, stops []services.ApprovedStop,
	promoCode string, discountSantim int64, isCash bool) (*CompleteRideContract, error) {
	if ride == nil {
		return nil, ErrRideNotFound
	}
	c := &CompleteRideContract{
		RideID:         ride.ID,
		DriverUserID:   driverUserID,
		DriverProfile:  driverProfile,
		RiderUserID:    ride.UserID,
		Status:         ride.Status,
		Snapshot:       snapshot,
		ApprovedStops:  stops,
		PromoCode:      promoCode,
		DiscountSantim: discountSantim,
		IsCash:         isCash,
		Currency:       ride.Currency,
		SnapshotKey:    snapshotKeyOf(snapshot),
	}
	c.SettlementEventID = ride.ID
	return c, nil
}

// Validate enforces every completion precondition, fail-closed:
//   - assigned-driver ownership (ErrCompletionUnauthorized),
//   - legal status transition in_progress -> completed (ErrCompletionStateInvalid),
//   - presence + integrity + ETB currency of the frozen contract,
//   - exact santim reconciliation between rides.fare_amount and the quote,
//   - non-negative approved additions and discount.
func (c *CompleteRideContract) Validate() error {
	if c.DriverProfile == uuid.Nil {
		return ErrCompletionUnauthorized
	}
	probe := &entities.Ride{Status: c.Status}
	if err := probe.TransitionTo(entities.RideStatusCompleted); err != nil {
		return ErrCompletionStateInvalid
	}
	if c.Snapshot == nil {
		return fmt.Errorf("%w: ride %s", ErrCompletionMissingContract, c.RideID)
	}
	if err := c.Snapshot.Validate(); err != nil {
		return fmt.Errorf("%w: %v", ErrCompletionMissingContract, err)
	}
	if c.Snapshot.RideID != c.RideID {
		return fmt.Errorf("%w: snapshot %s belongs to ride %s, not %s",
			ErrCompletionMissingContract, c.Snapshot.ID, c.Snapshot.RideID, c.RideID)
	}
	if c.Currency != "" && c.Currency != entities.CurrencyETB {
		return fmt.Errorf("%w: ride currency %q", ErrCompletionCurrency, c.Currency)
	}
	if services.MajorToSantim(c.Snapshot.QuotedTotalBirr()) != c.Snapshot.QuotedTotalSantim {
		return fmt.Errorf("%w: snapshot total %d santim does not round-trip its major-unit view",
			ErrCompletionFareDrift, c.Snapshot.QuotedTotalSantim)
	}
	if c.DiscountSantim < 0 {
		return ErrCompletionNegativeAddition
	}
	for _, st := range c.ApprovedStops {
		if st.FixedFeeSantim < 0 || st.WaitingChargeSan < 0 {
			return ErrCompletionNegativeAddition
		}
	}
	return nil
}

// FinalFareInput projects the validated contract onto the pure payable
// computation consumed by FinalFareService (§2.5 formula). Because the input
// contains only frozen/approved integers, the result is deterministic across
// retries and identical for cash and electronic settlement paths.
func (c *CompleteRideContract) FinalFareInput() services.FinalFareInput {
	return services.FinalFareInput{
		Snapshot:       c.Snapshot,
		Stops:          c.ApprovedStops,
		DiscountSantim: c.DiscountSantim,
	}
}

func snapshotKeyOf(s *entities.FareSnapshot) string {
	if s == nil {
		return ""
	}
	return s.IdempotencyKey
}
