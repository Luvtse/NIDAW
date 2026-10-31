// Package commands — NIDAW FARE INTEGRITY (Phase 2): rider-approved stops.
//
// ApproveRideStopHandler is the single authorized entry point that turns a
// planned intermediate stop into part of the PRICING CONTRACT. The policy it
// enforces end to end:
//
//   - A stop becomes chargeable ONLY through an explicit rider approval made
//     against the DISCLOSED amounts (fixed fee + conditional waiting charge)
//     returned by the quote preview. No approval => no charge, ever.
//   - Approval is exactly-once per (ride, seq). A replayed or double-tapped
//     approval returns ErrStopAlreadyApproved — it never mints a second fee
//     and never re-freezes the amount under a newer config value.
//   - Only the ride's owner (the authenticated rider subject from the JWT)
//     may approve. Drivers cannot create or accept rider-requested stops on
//     the rider's behalf; they can only run the server-recorded timer for a
//     stop the rider already approved (see StopChargeService timer methods).
//   - The stop must exist on the ride (ride_stops.seq, migration 012) — you
//     cannot be charged for a waypoint that was never added to the trip.
//   - Every approval requires a frozen booking contract (fare snapshot). A
//     stop cannot join an unpriced ride: the waiting charge is defined as a
//     fraction of the ORIGINAL booking fare, so without F0 there is nothing
//     transparent to disclose and the request fails closed.
//
// Persistence itself is delegated to services.StopChargeService, the sole
// writer of ride_stop_charges rows (migration 028), keeping one code path
// between "rider tapped confirm" and "settlement sums S and W".
package commands

import (
	"context"
	"errors"
	"fmt"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"

	"github.com/google/uuid"
)

// ============================================================================
// ERRORS
// ============================================================================

var (
	// ErrApproveStopNoContract: the ride has no frozen fare snapshot. Stops
	// price themselves against F0; without a contract there is no disclosed,
	// auditable amount, so approval is refused rather than repriced on the fly.
	ErrApproveStopNoContract = errors.New("cannot approve a stop without the frozen booking contract")

	// ErrApproveStopNotFound: the referenced ride does not exist. Stable code
	// the HTTP layer maps to 404 without leaking existence details.
	ErrApproveStopNotFound = errors.New("ride not found")
)

// ============================================================================
// APPROVAL STORE PORT
// ============================================================================

// RideStopLister loads the ride's ordered intermediate stops. Declared here
// (rather than importing the queries package) so the handler stays testable
// with a tiny fake and the application layer keeps its dependency direction.
type RideStopLister interface {
	ListStops(ctx context.Context, rideID uuid.UUID) ([]entities.RideStop, error)
}

// FareSnapshotGetter loads the immutable booking contract by ride id — the
// same read FinalizeFare performs at settlement.
type FareSnapshotGetter interface {
	GetSnapshotByRideID(ctx context.Context, rideID uuid.UUID) (*entities.FareSnapshot, error)
}

// StopApprovalStore is the write/disclose port ApproveRideStopHandler
// depends on. *services.StopChargeService satisfies it directly; tests inject
// fakes. Snapshot reads come from FareSnapshotGetter separately so the whole
// production graph composes from existing single-writer components:
// PostgresFareSnapshotRepository (contract reads) + StopChargeService (the
// sole writer of ride_stop_charges).
type StopApprovalStore interface {
	// QuoteStop returns the authoritative disclosure preview for one stop,
	// computed against the frozen booking fare F0 (non-compounding base).
	QuoteStop(ctx context.Context, rideID uuid.UUID, seq int) (*services.StopQuotePreview, error)

	// ApproveStop persists the exactly-once rider approval with the frozen
	// fixed fee. Returns entities.ErrStopAlreadyApproved on replay and an
	// ownership/validation error when the caller is not the ride's rider.
	ApproveStop(ctx context.Context, rideID, riderUserID uuid.UUID, seq int) (*entities.StopCharge, error)
}

// ============================================================================
// COMMAND / RESULT
// ============================================================================

// ApproveRideStopCommand carries ONLY trusted server-side identity plus the
// stop sequence. There is deliberately no fee field a client could submit:
// the payable amounts come exclusively from the versioned policy and the
// frozen contract, both resolved inside Execute.
type ApproveRideStopCommand struct {
	RideID      uuid.UUID
	RiderUserID uuid.UUID // authenticated rider subject (JWT user id)
	Seq         int       // 1-based stop sequence matching ride_stops.seq
}

// ApproveRideStopResult echoes the persisted approval AND the full disclosure
// so the consumer app renders exactly what is stored — including the waiting
// charge that applies if the server-recorded dwell reaches the threshold.
type ApproveRideStopResult struct {
	RideID          uuid.UUID `json:"ride_id"`
	Seq             int       `json:"seq"`
	StopFeeSantim   int64     `json:"stop_fee_santim"`
	PolicyVersion   string    `json:"policy_version"`
	Currency        string    `json:"currency"`
	ApprovedByRider bool      `json:"approved_by_rider"`

	// Disclosure fields (all integer ETB santim) — identical numbers the rider
	// saw BEFORE approval and the numbers settlement will sum.
	WaitingChargeIfLongSantim int64 `json:"waiting_charge_if_long_santim"`
	WaitingThresholdMinutes   int   `json:"waiting_threshold_minutes"`
	OriginalBookingFareSantim int64 `json:"original_booking_fare_santim"`
}

// ============================================================================
// HANDLER
// ============================================================================

// ApproveRideStopHandler validates and persists rider-approved stops and
// their quoted charges (§2.4). Safe for concurrent use: the underlying store
// serializes approvals on the (ride_id, seq) primary key.
type ApproveRideStopHandler struct {
	stops     RideStopLister
	snapshots FareSnapshotGetter
	approvals StopApprovalStore
}

// NewApproveRideStopHandler wires the command. All collaborators are
// mandatory; money paths fail loudly rather than half-working.
func NewApproveRideStopHandler(stops RideStopLister, snapshots FareSnapshotGetter, approvals StopApprovalStore) *ApproveRideStopHandler {
	return &ApproveRideStopHandler{stops: stops, snapshots: snapshots, approvals: approvals}
}

// NewApproveRideStopHandlerFromDB builds the production graph against an
// existing pool: stop listing straight from ride_stops, contract reads via
// the Phase 1 snapshot repository, and approvals through the sole
// stop-charge writer service.
func NewApproveRideStopHandlerFromDB(db *database.Postgres) *ApproveRideStopHandler {
	return NewApproveRideStopHandler(
		pgRideStopLister{db: db},
		NewPostgresFareSnapshotRepository(db),
		services.NewStopChargeService(db),
	)
}

// Execute approves one stop after verifying: valid seq → stop exists on the
// ride → frozen contract present → rider-owned exactly-once approval. The
// returned result is the persisted row state, never an in-memory guess.
func (h *ApproveRideStopHandler) Execute(ctx context.Context, cmd ApproveRideStopCommand) (*ApproveRideStopResult, error) {
	if h.stops == nil || h.snapshots == nil || h.approvals == nil {
		return nil, errors.New("approve ride stop: collaborators not configured")
	}

	// 1. Sequence bounds first — cheap rejection before any I/O.
	if cmd.Seq < 1 || cmd.Seq > entities.MaxRideStops {
		return nil, fmt.Errorf("%w: stop %d out of range (1..%d)",
			entities.ErrStopSeqOutOfRange, cmd.Seq, entities.MaxRideStops)
	}

	// 2. The stop must actually be on the ride. Charging for a waypoint nobody
	//    added is the exact "surprise at trip completion" failure mode §2.4
	//    forbids.
	rideStops, err := h.stops.ListStops(ctx, cmd.RideID)
	if err != nil {
		return nil, fmt.Errorf("list ride stops: %w", err)
	}
	found := false
	for _, s := range rideStops {
		if s.Seq == cmd.Seq {
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("%w: ride has no stop #%d", entities.ErrStopSeqOutOfRange, cmd.Seq)
	}

	// 3. The frozen booking contract must exist — the waiting charge is a
	//    fraction of F0 and the disclosure must reference real numbers. Any
	//    read/validation failure maps to ErrApproveStopNoContract so callers
	//    get one honest, stable code ("no approvable contract") instead of a
	//    raw storage error.
	snapshot, err := h.snapshots.GetSnapshotByRideID(ctx, cmd.RideID)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrApproveStopNoContract, err)
	}
	if snapshot == nil {
		return nil, ErrApproveStopNoContract
	}
	if err := snapshot.Validate(); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrApproveStopNoContract, err)
	}

	// 4. Authoritative disclosure for THIS stop against F0 (non-compounding
	//    base by construction — QuoteStopPreview computes the waiting charge
	//    from the original booking fare only).
	preview, err := h.approvals.QuoteStop(ctx, cmd.RideID, cmd.Seq)
	if err != nil {
		return nil, err
	}

	// 5. Persist the exactly-once rider approval (owner-checked inside the
	//    store; replays surface ErrStopAlreadyApproved unchanged so retries
	//    never double the fee).
	charge, err := h.approvals.ApproveStop(ctx, cmd.RideID, cmd.RiderUserID, cmd.Seq)
	if err != nil {
		return nil, err
	}

	return &ApproveRideStopResult{
		RideID:                    cmd.RideID,
		Seq:                       charge.Seq,
		StopFeeSantim:             charge.StopFeeSantim,
		PolicyVersion:             charge.StopPolicyVer,
		Currency:                  entities.CurrencyETB,
		ApprovedByRider:           charge.ApprovedByRider,
		WaitingChargeIfLongSantim: preview.WaitingChargeIfLongSantim,
		WaitingThresholdMinutes:   preview.WaitingThresholdMinutes,
		OriginalBookingFareSantim: snapshot.QuotedTotalSantim,
	}, nil
}

// ============================================================================
// INTERNALS
// ============================================================================

// pgRideStopLister reads ride_stops rows (migration 012) in visit order.
type pgRideStopLister struct {
	db *database.Postgres
}

func (l pgRideStopLister) ListStops(ctx context.Context, rideID uuid.UUID) ([]entities.RideStop, error) {
	rows, err := l.db.Query(ctx, `
		SELECT seq, lat, lng, COALESCE(address, '')
		  FROM ride_stops
		 WHERE ride_id = $1
		 ORDER BY seq`, rideID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []entities.RideStop
	for rows.Next() {
		var s entities.RideStop
		if err := rows.Scan(&s.Seq, &s.Lat, &s.Lng, &s.Address); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
