// Package commands — NIDAW FARE INTEGRITY (Phase 1/3): finalize-the-fare
// command.
//
// FinalizeFareHandler is the single authorized entry point for turning a
// frozen booking contract into a settled, persisted payable — EXACTLY ONCE.
// It composes the pieces Phase 1 already shipped:
//
//   - CompleteRideContract (this package): validated authorization + contract
//     preconditions (assigned driver only, in_progress only, ETB only, fare
//     reconciles with the frozen quote to the santim).
//   - services.FinalFareService: the pure §2.5 formula
//     F_payable = max(0, F0 + S + W - P) over integer santim. Actual trip
//     metrics are NOT inputs — detours, delays and manipulated driver reports
//     can never change the result.
//   - The durable outbox (ride_completed_events, keyed by the ride UUID) plus
//     the ledger's own "ride:debit:<ride_id>" idempotency: a retried or
//     concurrent finalization returns the SAME stored result and publishes at
//     most one settlement obligation.
//
// Persistence model: rides.fare_amount / currency / tip and the outbox row
// commit inside ONE database transaction. If the event bus is unavailable the
// transaction still commits (outbox pending) so the settlement obligation is
// never lost; the background SettlementOutbox re-publisher drains it later.
// A failed payment downstream likewise cannot rewrite the finalized fare —
// the payable lives in the frozen contract and the persisted breakdown.
package commands

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/eventbus"

	"github.com/google/uuid"
)

// ============================================================================
// ERRORS
// ============================================================================

var (
	// ErrFinalizeAlreadySettled surfaces on a REPLAYED finalization whose
	// settlement row exists but whose stored payload cannot be re-verified
	// against the contract. Callers must treat this as "already finalized":
	// never recompute, never republish, never double-charge.
	ErrFinalizeAlreadySettled = errors.New("fare already finalized for this ride")
)

// ============================================================================
// COMMAND / RESULT
// ============================================================================

// FinalizeFareCommand carries ONLY trusted server-side identity. There is
// deliberately no fare/distance/duration field a client could manipulate:
// everything monetary is loaded from the database inside Execute.
type FinalizeFareCommand struct {
	RideID       uuid.UUID
	DriverUserID uuid.UUID // authenticated driver subject (JWT user id)

	// Operations-only actuals recorded on the ride row for analytics/safety.
	// They NEVER enter the money math (see FinalFareService.Compute inputs).
	ActualDistanceKm  float64
	ActualDurationMin int

	// PromoDiscountSantim overrides the request-time projection when the
	// promotions port has produced an authoritative receipt-time number.
	// Zero keeps the stored ride-level discount. Must be >= 0.
	PromoDiscountSantim int64
}

// FinalizeFareResult is the persisted, retry-stable finalization outcome. All
// amounts are integer ETB santim; major-unit views are derived at display
// boundaries only.
type FinalizeFareResult struct {
	RideID         uuid.UUID `json:"ride_id"`
	FareSnapshot   uuid.UUID `json:"fare_snapshot_id"`
	SettlementID   uuid.UUID `json:"settlement_id"` // deterministic: == ride id
	IdempotencyKey string    `json:"idempotency_key"`

	BookingFareSantim    int64  `json:"booking_fare_santim"`    // F0
	StopFeesSantim       int64  `json:"stop_fees_santim"`       // S
	WaitingChargesSantim int64  `json:"waiting_charges_santim"` // W
	GrossFareSantim      int64  `json:"gross_fare_santim"`      // F0+S+W
	DiscountSantim       int64  `json:"discount_santim"`        // P applied
	PayableSantim        int64  `json:"payable_fare_santim"`    // rider debit
	CommissionSantim     int64  `json:"commission_santim"`      // platform take
	DriverEarningsSantim int64  `json:"driver_earnings_santim"` // gross - commission
	TipSantim            int64  `json:"tip_santim"`             // separate credit per tip policy
	Currency             string `json:"currency"`               // always ETB

	// Breakdown is the itemized payable receipts/apps render verbatim.
	Breakdown []services.FinalFareLine `json:"breakdown,omitempty"`

	// AlreadyFinalized is true when this call replayed a previous
	// finalization: the numbers below are the ORIGINAL stored values.
	AlreadyFinalized bool `json:"already_finalized"`
	// Published reports whether the settlement event reached the bus inline;
	// false means the durable outbox owns the retry (obligation NOT lost).
	Published bool `json:"published"`
	// PendingCashCollection marks cash rides: same payable, settlement emitted
	// at collection confirmation instead.
	PendingCashCollection bool `json:"pending_cash_collection"`
}

// ============================================================================
// PORTS
// ============================================================================

// FinalizeStopCharger is the approved-stop port (same shape as StopCharger,
// declared locally so the finalize path stays wired even when callers build
// the handler without the full lifecycle graph).
type FinalizeStopCharger interface {
	SettlementCharges(ctx context.Context, rideID uuid.UUID) ([]services.ApprovedStop, error)
}

// ============================================================================
// HANDLER
// ============================================================================

// FinalizeFareHandler authorizes, computes, persists and publishes the final
// payable exactly once per ride. Safe for concurrent use: duplicate attempts
// serialize on the terminal-status UPDATE (only one wins) and on the outbox's
// deterministic event key.
type FinalizeFareHandler struct {
	db         *database.Postgres
	eventBus   eventbus.EventBus
	snapshots  FareSnapshotRepository
	finalFare  *services.FinalFareService
	stopCharge FinalizeStopCharger // nil => rides with approved stops refuse to finalize
}

// NewFinalizeFareHandler wires the finalize path against an existing pool.
func NewFinalizeFareHandler(db *database.Postgres, eventBus eventbus.EventBus, stopCharge FinalizeStopCharger) *FinalizeFareHandler {
	return &FinalizeFareHandler{
		db:         db,
		eventBus:   eventBus,
		snapshots:  NewPostgresFareSnapshotRepository(db),
		finalFare:  services.NewFinalFareService(),
		stopCharge: stopCharge,
	}
}

// Execute performs the full finalize flow. See file header for the contract.
func (h *FinalizeFareHandler) Execute(ctx context.Context, cmd FinalizeFareCommand) (*FinalizeFareResult, error) {
	if h.db == nil {
		return nil, errors.New("finalize fare: database not configured")
	}
	if cmd.PromoDiscountSantim < 0 {
		return nil, ErrCompletionNegativeAddition
	}

	// --- 1. Authorization ------------------------------------------------
	driverProfile, err := h.resolveDriverID(ctx, cmd.DriverUserID)
	if err != nil {
		return nil, err
	}
	ride, err := h.loadRideForFinalize(ctx, cmd.RideID)
	if err != nil {
		return nil, err
	}
	if ride.DriverID == nil || *ride.DriverID != driverProfile {
		return nil, ErrForbidden
	}

	// --- 2. Replay short-circuit ------------------------------------------
	// A ride already past in_progress was finalized by the winning attempt.
	// Return its STORED numbers; never recompute, never republish. This is
	// what makes duplicate completion requests harmless (§ mandatory test:
	// "duplicate completion requests cannot double-charge or double-credit").
	if ride.Status == entities.RideStatusCompleted || ride.Status == entities.RideStatusPaid {
		return h.replayStoredResult(ctx, ride)
	}

	// --- 3. Load the frozen contract + approved additions -----------------
	snapshot, err := h.snapshots.GetSnapshotByRideID(ctx, ride.ID)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrFareCalcFailed, err)
	}
	var approvedStops []services.ApprovedStop
	if h.stopCharge != nil {
		approvedStops, err = h.stopCharge.SettlementCharges(ctx, ride.ID)
		if err != nil {
			return nil, fmt.Errorf("%w: load approved stop charges: %v", ErrFareCalcFailed, err)
		}
	} else {
		var stray int
		if err := h.db.QueryRow(ctx,
			`SELECT count(*) FROM ride_stop_charges WHERE ride_id = $1 AND approved_by_rider`, ride.ID).Scan(&stray); err != nil {
			return nil, fmt.Errorf("check approved stop charges: %w", err)
		}
		if stray > 0 {
			return nil, fmt.Errorf("%w: ride %s has %d approved stop charge(s) but the finalize path is not wired for stops; refusing to under-settle",
				ErrFareCalcFailed, ride.ID, stray)
		}
	}

	discountSantim := services.MajorToSantim(ride.PromoDiscount)
	if cmd.PromoDiscountSantim > discountSantim {
		discountSantim = cmd.PromoDiscountSantim
	}
	if discountSantim < 0 {
		discountSantim = 0
	}

	// --- 4. Validate the completion contract (fail closed) ----------------
	contract, err := NewCompleteRideContract(ride, snapshot, driverProfile, cmd.DriverUserID,
		approvedStops, ride.PromoCode, discountSantim, ride.IsCashRide())
	if err != nil {
		return nil, err
	}
	if err := contract.Validate(); err != nil {
		return nil, err
	}

	// --- 5. Deterministic payable (§2.5) ----------------------------------
	res, err := h.finalFare.Compute(contract.FinalFareInput())
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrFareCalcFailed, err)
	}
	commissionSantim := computePlatformFeeSantim(res.GrossFareSantim)
	driverEarningsSantim := res.GrossFareSantim - commissionSantim
	appliedDiscountSantim := res.GrossFareSantim - res.PayableSantim
	tipSantim := services.MajorToSantim(ride.TipAmount)
	if tipSantim < 0 {
		tipSantim = 0
	}

	breakdownJSON, err := json.Marshal(res.Lines)
	if err != nil {
		return nil, fmt.Errorf("%w: encode final fare breakdown: %v", ErrFareCalcFailed, err)
	}

	actualDistance := ride.DistanceKm
	actualDuration := ride.DurationMinutes
	if cmd.ActualDistanceKm > 0 {
		actualDistance = cmd.ActualDistanceKm
	}
	if cmd.ActualDurationMin > 0 {
		actualDuration = cmd.ActualDurationMin
	}

	payload := map[string]interface{}{
		"ride_id":                 ride.ID.String(),
		"driver_id":               h.driverUserIDString(ctx, driverProfile),
		"user_id":                 ride.UserID.String(),
		"actual_distance":         actualDistance, // operations-only
		"actual_duration":         actualDuration, // operations-only
		"final_fare":              services.SantimToMajor(res.GrossFareSantim),
		"driver_earnings":         services.SantimToMajor(driverEarningsSantim),
		"platform_fee":            services.SantimToMajor(commissionSantim),
		"currency":                entities.CurrencyETB,
		"payment_method_type":     ride.PaymentMethodType,
		"fare_snapshot_id":        snapshot.ID.String(),
		"pending_cash_collection": contract.IsCash,
		"promo_code":              contract.PromoCode,
		"promo_discount":          services.SantimToMajor(appliedDiscountSantim),
		"charge_amount":           services.SantimToMajor(res.PayableSantim),
		// ---- Authoritative integer-santim settlement contract -------------
		"booking_fare_santim":    res.BookingFareSantim,
		"stop_fees_santim":       res.StopFeesSantim,
		"waiting_charges_santim": res.WaitingSantim,
		"gross_fare_santim":      res.GrossFareSantim,
		"discount_santim":        appliedDiscountSantim,
		"payable_fare_santim":    res.PayableSantim,
		"commission_santim":      commissionSantim,
		"driver_earnings_santim": driverEarningsSantim,
		"tip_santim":             tipSantim,
		"final_fare_lines":       string(breakdownJSON),
		"settlement_idempotency": res.IdempotencyKey,
	}

	rec := settlementRecord{
		EventID:      ride.ID, // deterministic: one settlement per ride, ever
		RideID:       ride.ID,
		DriverUserID: mustParseUUID(payload["driver_id"].(string)),
		Currency:     entities.CurrencyETB,
		Payload:      payload,
	}

	// --- 6. Fast-path publish BEFORE the transaction -----------------------
	// Bus failure is NOT fatal: the outbox row committed below guarantees the
	// settlement obligation survives and retries (mandatory scenario: "a
	// failed payment or unavailable event bus does not change the finalized
	// fare or lose the settlement obligation").
	settled := false
	if !contract.IsCash && h.eventBus != nil {
		if err := h.publishRideCompleted(ctx, payload); err == nil {
			settled = true
			rec.DirectPublished = true
		}
	}

	// --- 7. Persist terminal state + outbox atomically --------------------
	if err := h.persistFinalization(ctx, ride.ID, res, commissionSantim,
		actualDistance, actualDuration, appliedDiscountSantim, rec, contract.IsCash); err != nil {
		return nil, err
	}

	return &FinalizeFareResult{
		RideID:                ride.ID,
		FareSnapshot:          snapshot.ID,
		SettlementID:          ride.ID,
		IdempotencyKey:        res.IdempotencyKey,
		BookingFareSantim:     res.BookingFareSantim,
		StopFeesSantim:        res.StopFeesSantim,
		WaitingChargesSantim:  res.WaitingSantim,
		GrossFareSantim:       res.GrossFareSantim,
		DiscountSantim:        appliedDiscountSantim,
		PayableSantim:         res.PayableSantim,
		CommissionSantim:      commissionSantim,
		DriverEarningsSantim:  driverEarningsSantim,
		TipSantim:             tipSantim,
		Currency:              entities.CurrencyETB,
		Breakdown:             res.Lines,
		Published:             settled,
		PendingCashCollection: contract.IsCash,
	}, nil
}

// ============================================================================
// INTERNALS
// ============================================================================

func (h *FinalizeFareHandler) resolveDriverID(ctx context.Context, userID uuid.UUID) (uuid.UUID, error) {
	var driverID uuid.UUID
	err := h.db.QueryRow(ctx, `SELECT id FROM drivers WHERE user_id = $1`, userID).Scan(&driverID)
	if err != nil {
		return uuid.Nil, ErrForbidden
	}
	return driverID, nil
}

func (h *FinalizeFareHandler) driverUserIDString(ctx context.Context, driverProfile uuid.UUID) string {
	var uid uuid.UUID
	if err := h.db.QueryRow(ctx, `SELECT user_id FROM drivers WHERE id = $1`, driverProfile).Scan(&uid); err != nil {
		return ""
	}
	return uid.String()
}

func (h *FinalizeFareHandler) loadRideForFinalize(ctx context.Context, rideID uuid.UUID) (*entities.Ride, error) {
	base := lifecycleBase{db: h.db}
	return base.loadRide(ctx, rideID)
}

func (h *FinalizeFareHandler) publishRideCompleted(ctx context.Context, payload map[string]interface{}) error {
	base := lifecycleBase{db: h.db, eventBus: h.eventBus}
	return base.publishRideCompleted(ctx, payload)
}

// persistFinalization writes the completed status + authoritative money
// columns and enqueues the settlement outbox row in ONE transaction, guarded
// by `status = 'in_progress'` so concurrent finalizers cannot both win. The
// loser sees zero rows affected and replays the winner's stored result.
func (h *FinalizeFareHandler) persistFinalization(ctx context.Context, rideID uuid.UUID,
	res *services.FinalFareResult, commissionSantim int64,
	actualDistance float64, actualDuration int, appliedDiscountSantim int64,
	rec settlementRecord, isCash bool) error {
	won := false
	err := h.db.WithTx(ctx, func(tx *database.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE rides
			       SET status = 'completed',
			           fare_amount = $2, currency = $3,
			           distance_km = $4, duration_minutes = $5,
			           service_fee_component = $6,
			           promo_discount = $7,
			           completed_at = NOW(), updated_at = NOW()
			 WHERE id = $1 AND status = 'in_progress'`,
			rideID,
			services.SantimToMajor(res.GrossFareSantim),
			entities.CurrencyETB,
			actualDistance, actualDuration,
			services.SantimToMajor(commissionSantim),
			services.SantimToMajor(appliedDiscountSantim))
		if err != nil {
			return err
		}
		won = tag.RowsAffected() == 1
		if !won {
			return nil // lost the race: replay path reads the winner's row
		}
		if isCash {
			return nil // settlement deferred to collection confirmation (§3.1)
		}
		return enqueueRideCompleted(ctx, tx, rec)
	})
	if err != nil {
		return err
	}
	if won {
		return nil
	}
	// Lost the race — surface the winner's stored result instead of failing.
	ride, lerr := h.loadRideForFinalize(ctx, rideID)
	if lerr != nil {
		return lerr
	}
	if ride.Status != entities.RideStatusCompleted && ride.Status != entities.RideStatusPaid {
		return ErrCompletionStateInvalid
	}
	return nil
}

// replayStoredResult reconstructs the FINALIZED result from the persisted
// contract + ride row for a repeated completion call. Because every amount
// derives deterministically from the immutable snapshot, the replayed numbers
// equal the original ones to the santim — no double charge, no drift.
func (h *FinalizeFareHandler) replayStoredResult(ctx context.Context, ride *entities.Ride) (*FinalizeFareResult, error) {
	if ride.FareSnapshotID == nil {
		return nil, fmt.Errorf("%w: ride %s completed without a linked contract", ErrFinalizeAlreadySettled, ride.ID)
	}
	snapshot, err := h.snapshots.GetSnapshotByRideID(ctx, ride.ID)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrFinalizeAlreadySettled, err)
	}
	var stops []services.ApprovedStop
	if h.stopCharge != nil {
		stops, err = h.stopCharge.SettlementCharges(ctx, ride.ID)
		if err != nil {
			return nil, fmt.Errorf("%w: reload stop charges: %v", ErrFinalizeAlreadySettled, err)
		}
	}
	discount := services.MajorToSantim(ride.PromoDiscount)
	if discount < 0 {
		discount = 0
	}
	res, err := h.finalFare.Compute(services.FinalFareInput{
		Snapshot:       snapshot,
		Stops:          stops,
		DiscountSantim: discount,
	})
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrFinalizeAlreadySettled, err)
	}
	// Sanity: the stored fare_amount must equal the recomputed gross, else the
	// row drifted after finalization — report honestly rather than masking it.
	if services.MajorToSantim(ride.FareAmount) != res.GrossFareSantim {
		return nil, fmt.Errorf("%w: stored fare %.2f diverges from contract gross %d santim",
			ErrFinalizeAlreadySettled, ride.FareAmount, res.GrossFareSantim)
	}
	commissionSantim := computePlatformFeeSantim(res.GrossFareSantim)
	tipSantim := services.MajorToSantim(ride.TipAmount)
	if tipSantim < 0 {
		tipSantim = 0
	}
	return &FinalizeFareResult{
		RideID:                ride.ID,
		FareSnapshot:          snapshot.ID,
		SettlementID:          ride.ID,
		IdempotencyKey:        res.IdempotencyKey,
		BookingFareSantim:     res.BookingFareSantim,
		StopFeesSantim:        res.StopFeesSantim,
		WaitingChargesSantim:  res.WaitingSantim,
		GrossFareSantim:       res.GrossFareSantim,
		DiscountSantim:        res.GrossFareSantim - res.PayableSantim,
		PayableSantim:         res.PayableSantim,
		CommissionSantim:      commissionSantim,
		DriverEarningsSantim:  res.GrossFareSantim - commissionSantim,
		TipSantim:             tipSantim,
		Currency:              entities.CurrencyETB,
		Breakdown:             res.Lines,
		AlreadyFinalized:      true,
		Published:             ride.Status == entities.RideStatusPaid || !ride.IsCashRide(),
		PendingCashCollection: ride.IsCashRide() && ride.Status == entities.RideStatusCompleted,
	}, nil
}

func mustParseUUID(s string) uuid.UUID {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.Nil
	}
	return id
}
