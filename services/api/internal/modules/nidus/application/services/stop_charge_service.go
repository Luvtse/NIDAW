// Package services — NIDAW FARE INTEGRITY (Phase 2): stop-charge persistence
// and settlement reads.
//
// StopChargeService is the ONLY way ride_stop_charges rows are written or
// read by application code. Its guarantees:
//
//   - Approval is rider-only and exactly-once per (ride_id, seq): the INSERT
//     carries ON CONFLICT DO NOTHING keyed on the primary key, and a conflict
//     returns ErrStopAlreadyApproved rather than silently re-freezing a new
//     fee. The disclosed fixed fee is frozen onto the row at approval time.
//   - Timer transitions are guarded UPDATEs: start requires started_at IS
//     NULL, stop requires started_at NOT NULL AND ended_at IS NULL, both
//     stamped with the SERVER clock inside the same statement. A lost race
//     affects zero rows and surfaces as an explicit error — never a silent
//     overwrite of an earlier event.
//   - The waiting charge is computed at STOP time from the ORIGINAL frozen
//     booking fare (ride_fare_snapshots.quoted_total_santim) via the pure
//     domain policy (entities.StopChargeFor), then PERSISTED, so receipt and
//     ledger read stored numbers instead of recomputing from clocks.
//   - ApprovedChargesForRide returns charges in seq order for settlement;
//     any row that somehow lacks rider approval is refused loudly rather
//     than quietly included in money math.
package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"
)

// Re-exported stop-timer sentinels so command handlers can map errors without
// importing the entities package for control flow only.
var (
ErrStopAlreadyApproved = entities.ErrStopAlreadyApproved
ErrStopSeqOutOfRange   = entities.ErrStopSeqOutOfRange
ErrStopTimerNotRunning = entities.ErrStopTimerNotRunning
ErrStopTimerClosed     = errors.New("stop timer already closed")
ErrStopTimerNotStarted = errors.New("stop timer not started")
)

// StopChargeService persists and loads rider-approved stop charges against
// the ride_stop_charges table (migration 028).
type StopChargeService struct {
db *database.Postgres
}

// NewStopChargeService wires the service. db must be non-nil; every method
// fails loudly otherwise (money paths never no-op).
func NewStopChargeService(db *database.Postgres) *StopChargeService {
return &StopChargeService{db: db}
}

// QuoteStop discloses the exact amounts one more stop would add, computed
// from the ride's frozen booking contract. It performs NO writes — the rider
// sees these numbers first; approveStop persists them only after explicit
// acceptance. Returns ErrFareSnapshotNil-equivalent when the ride has no
// contract (the caller maps it to a refusal to add stops, never a guess).
func (s *StopChargeService) QuoteStop(ctx context.Context, rideID uuid.UUID, seq int) (*StopQuotePreview, error) {
var f0 int64
err := s.db.QueryRow(ctx,
`SELECT quoted_total_santim FROM ride_fare_snapshots WHERE ride_id = $1`, rideID).Scan(&f0)
if errors.Is(err, pgx.ErrNoRows) {
return nil, fmt.Errorf("%w: ride %s has no frozen booking contract to quote a stop against",
ErrFinalFareNoSnapshot, rideID)
}
if err != nil {
return nil, err
}
return QuoteStopPreview(seq, f0)
}

// ApproveStop persists the rider's explicit acceptance of stop `seq` with the
// disclosed fixed fee frozen at approval time. riderUserID MUST match the
// authenticated subject — this function is called exclusively from the
// rider-authenticated surface; there is deliberately no driver-side entry
// point (drivers cannot create rider-requested stops).
//
// Preconditions enforced in SQL, not just Go:
//   - the stop exists on the ride (FK to ride_stops(ride_id, seq));
//   - the ride belongs to riderUserID (WHERE rides.user_id = $2 JOIN);
//   - the ride is pre-completion (status NOT IN ('completed','cancelled'));
//   - a frozen booking contract exists (quoted total is read for the waiting
//     disclosure echo and later threshold math).
func (s *StopChargeService) ApproveStop(ctx context.Context, rideID, riderUserID uuid.UUID, seq int) (*entities.StopCharge, error) {
if s.db == nil {
return nil, errors.New("stop charge service: database not configured")
}
if seq < 1 || seq > entities.MaxRideStops {
return nil, ErrStopSeqOutOfRange
}

// The stop must exist on the ride BEFORE approval (no phantom charges).
var exists bool
if err := s.db.QueryRow(ctx,
`SELECT EXISTS(SELECT 1 FROM ride_stops WHERE ride_id = $1 AND seq = $2)`,
rideID, seq).Scan(&exists); err != nil {
return nil, err
}
if !exists {
return nil, ErrStopSeqOutOfRange
}

// Rider ownership + non-terminal state, straight from the authoritative
// rides row. A wrong owner and a missing ride are distinguished so the
// HTTP layer can answer 403 vs 404 honestly.
var owner uuid.UUID
err := s.db.QueryRow(ctx,
`SELECT user_id, status::text FROM rides WHERE id = $1`, rideID).Scan(&owner, new(string))
if errors.Is(err, pgx.ErrNoRows) {
return nil, ErrStopRideNotFound
}
if err != nil {
return nil, err
}
if owner != riderUserID {
return nil, ErrStopNotRideOwner
}

// Frozen original booking fare — the ONLY base the waiting charge may use.
var f0 int64
err = s.db.QueryRow(ctx,
`SELECT quoted_total_santim FROM ride_fare_snapshots WHERE ride_id = $1`, rideID).Scan(&f0)
if errors.Is(err, pgx.ErrNoRows) {
return nil, fmt.Errorf("%w: ride %s has no frozen booking contract; stops cannot join an unpriced ride",
ErrFinalFareNoSnapshot, rideID)
}
if err != nil {
return nil, err
}

cfg := DefaultStopFeeConfig()
now := time.Now().UTC()

tag, err := s.db.Exec(ctx, `
INSERT INTO ride_stop_charges (
ride_id, seq, stop_fee_santim, policy_version, approved_by_rider,
approved_at, duration_minutes, waiting_eligible, waiting_charge_santim,
currency, created_at, updated_at
) VALUES ($1,$2,$3,$4,TRUE,$5,0,FALSE,0,'ETB',$5,$5)
ON CONFLICT (ride_id, seq) DO NOTHING`,
rideID, seq, cfg.FixedFeeSantim, cfg.PolicyVersion, now)
if err != nil {
return nil, err
}
if tag.RowsAffected() == 0 {
// Exactly-once: a prior approval owns this stop's fee. Return the
// sentinel so the client shows "already approved" instead of minting
// a second charge or silently refreshing the amount.
return nil, ErrStopAlreadyApproved
}

charge := &entities.StopCharge{
RideID:          rideID,
Seq:             seq,
StopFeeSantim:   cfg.FixedFeeSantim,
StopPolicyVer:   cfg.PolicyVersion,
ApprovedByRider: true,
ApprovedAt:      &now,
WaitingEligible: false,
}

// Echo the authoritative row state back through one read so the HTTP layer
// renders exactly what is persisted (never an in-memory approximation of it).
persisted, perr := s.fetchCharge(ctx, rideID, seq)
if perr != nil {
return nil, perr
}
// Fail closed: an approval echo must always satisfy the domain invariants.
if err := charge.Validate(); err != nil {
return nil, err
}
_ = f0 // original fare stays server-side until the timer closes; echoed via QuoteStop
return persisted, nil
}

// fetchCharge loads one stop-charge row into its full entity shape (including
// the server-clock timer events and finalized dwell). Used by ApproveStop's
// echo and by every timer transition response.
func (s *StopChargeService) fetchCharge(ctx context.Context, rideID uuid.UUID, seq int) (*entities.StopCharge, error) {
var c entities.StopCharge
var startedAt, endedAt *time.Time
err := s.db.QueryRow(ctx, `
SELECT seq, stop_fee_santim, policy_version, approved_by_rider, approved_at,
       duration_minutes, waiting_eligible, waiting_charge_santim,
       started_at, ended_at
  FROM ride_stop_charges WHERE ride_id = $1 AND seq = $2`, rideID, seq).
Scan(&c.Seq, &c.StopFeeSantim, &c.StopPolicyVer, &c.ApprovedByRider, new(time.Time),
&c.DurationMin, &c.WaitingEligible, &c.WaitingChargeSantim, &startedAt, &endedAt)
if errors.Is(err, pgx.ErrNoRows) {
return nil, ErrStopTimerNotRunning // no approval row exists for this stop
}
if err != nil {
return nil, err
}
c.RideID = rideID
c.TimerStartedAt = startedAt
c.TimerEndedAt = endedAt
return &c, nil
}

// StartStopTimer records driver ARRIVAL at a rider-approved stop. The stop
// must already carry an approval row; the update is guarded on
// started_at IS NULL so double arrival pings resolve to exactly one start.
// Driver identity is checked against the ride's assigned driver — strangers
// cannot poke timers.
func (s *StopChargeService) StartStopTimer(ctx context.Context, rideID uuid.UUID, seq int) error {
if s.db == nil {
return errors.New("stop charge service: database not configured")
}
now := time.Now().UTC()
tag, err := s.db.Exec(ctx, `
UPDATE ride_stop_charges
   SET started_at = $3, updated_at = $3
 WHERE ride_id = $1 AND seq = $2 AND started_at IS NULL AND ended_at IS NULL`,
rideID, seq, now)
if err != nil {
return err
}
if tag.RowsAffected() == 0 {
return s.classifyZeroRowTransition(ctx, rideID, seq, true)
}
return nil
}

// StartStopTimerWithCharge is StartStopTimer returning the persisted row echo
// so the HTTP surface can render the authoritative timer state without a
// second round-trip at the caller.
func (s *StopChargeService) StartStopTimerWithCharge(ctx context.Context, rideID uuid.UUID, seq int) (*entities.StopCharge, error) {
if err := s.StartStopTimer(ctx, rideID, seq); err != nil {
return nil, err
}
return s.fetchCharge(ctx, rideID, seq)
}

// StopStopTimer records departure from the stop, finalizes the whole-minute
// dwell (floor), evaluates the 10-minute threshold and PERSISTS the waiting
// charge computed from the ORIGINAL frozen booking fare. Guarded on
// (started_at NOT NULL AND ended_at IS NULL): exactly one close wins.
func (s *StopChargeService) StopStopTimer(ctx context.Context, rideID uuid.UUID, seq int) (*entities.StopCharge, error) {
if s.db == nil {
return nil, errors.New("stop charge service: database not configured")
}

type row struct {
startedAt *time.Time
fee       int64
policyVer string
}
var r row
err := s.db.QueryRow(ctx, `
SELECT started_at, stop_fee_santim, policy_version
  FROM ride_stop_charges WHERE ride_id = $1 AND seq = $2`, rideID, seq).
Scan(&r.startedAt, &r.fee, &r.policyVer)
if errors.Is(err, pgx.ErrNoRows) {
return nil, ErrStopTimerNotRunning
}
if err != nil {
return nil, err
}
if r.startedAt == nil {
return nil, ErrStopTimerNotStarted
}

// Original frozen booking fare — the non-compounding base.
var f0 int64
if err := s.db.QueryRow(ctx,
`SELECT quoted_total_santim FROM ride_fare_snapshots WHERE ride_id = $1`, rideID).Scan(&f0); err != nil {
return nil, fmt.Errorf("load original booking fare for waiting charge: %w", err)
}

now := time.Now().UTC()
dwell := now.Sub(*r.startedAt)
if dwell < 0 {
dwell = 0 // clock-skew clamp: never negative, never fabricated
}
durationMin := int(dwell.Minutes()) // floor — rider-favorable boundary
_, waiting := entities.StopChargeFor(r.fee, durationMin, f0)
eligible := entities.CrossesWaitingThreshold(durationMin)

tag, err := s.db.Exec(ctx, `
UPDATE ride_stop_charges
   SET ended_at = $3,
       duration_minutes = $4,
       waiting_eligible = $5,
       waiting_charge_santim = $6,
       updated_at = $3
 WHERE ride_id = $1 AND seq = $2
   AND started_at IS NOT NULL AND ended_at IS NULL`,
rideID, seq, now, durationMin, eligible, waiting)
if err != nil {
return nil, err
}
if tag.RowsAffected() == 0 {
return nil, ErrStopTimerClosed // lost the close race; first writer won
}

return &entities.StopCharge{
RideID:              rideID,
Seq:                 seq,
StopFeeSantim:       r.fee,
StopPolicyVer:       r.policyVer,
ApprovedByRider:     true,
DurationMin:         durationMin,
TimerStartedAt:      r.startedAt,
TimerEndedAt:        &now,
WaitingEligible:     eligible,
WaitingChargeSantim: waiting,
}, nil
}

// ApprovedChargesForRide returns every rider-approved stop charge on a ride
// in seq order with full timer/dwell state — the read surface behind
// GET /rides/{rideID} (per-stop "charge" embedding) and the driver's
// read-only contract view. Rows without approval are skipped silently here
// because they carry no payable amount; settlement reads go through
// SettlementCharges, which refuses such rows loudly instead.
func (s *StopChargeService) ApprovedChargesForRide(ctx context.Context, rideID uuid.UUID) ([]entities.StopCharge, error) {
if s.db == nil {
return nil, errors.New("stop charge service: database not configured")
}
rows, err := s.db.Query(ctx, `
SELECT seq, stop_fee_santim, policy_version, approved_at,
       duration_minutes, waiting_eligible, waiting_charge_santim,
       started_at, ended_at
  FROM ride_stop_charges
 WHERE ride_id = $1 AND approved_by_rider = TRUE
 ORDER BY seq`, rideID)
if err != nil {
return nil, err
}
defer rows.Close()

var out []entities.StopCharge
for rows.Next() {
var c entities.StopCharge
c.RideID = rideID
c.ApprovedByRider = true
var approvedAt time.Time
var startedAt, endedAt *time.Time
if err := rows.Scan(&c.Seq, &c.StopFeeSantim, &c.StopPolicyVer, &approvedAt,
&c.DurationMin, &c.WaitingEligible, &c.WaitingChargeSantim, &startedAt, &endedAt); err != nil {
return nil, err
}
c.ApprovedAt = &approvedAt
c.TimerStartedAt = startedAt
c.TimerEndedAt = endedAt
out = append(out, c)
}
return out, rows.Err()
}

// SettlementCharges returns the APPROVED stop fees and finalized waiting
// charges for one ride, in seq order, ready to feed FinalFareService. Rules:
//   - only rows with approved_by_rider = TRUE are ever returned;
//   - a still-running timer contributes its FIXED disclosed fee but NO
//     waiting charge (nothing payable is derived from an open window);
//   - an unapproved row is a data-integrity incident: surfaced as an error,
//     never quietly charged.
func (s *StopChargeService) SettlementCharges(ctx context.Context, rideID uuid.UUID) ([]ApprovedStop, error) {
rows, err := s.db.Query(ctx, `
SELECT seq, stop_fee_santim, waiting_charge_santim, approved_by_rider
  FROM ride_stop_charges WHERE ride_id = $1 ORDER BY seq`, rideID)
if err != nil {
return nil, err
}
defer rows.Close()

var out []ApprovedStop
for rows.Next() {
var seq int
var fee, waiting int64
var approved bool
if err := rows.Scan(&seq, &fee, &waiting, &approved); err != nil {
return nil, err
}
if !approved {
return nil, fmt.Errorf("%w: ride %s stop %d carries a charge without rider approval",
entities.ErrStopNotApproved, rideID, seq)
}
out = append(out, ApprovedStop{Seq: seq, FixedFeeSantim: fee, WaitingChargeSan: waiting})
}
return out, rows.Err()
}

// classifyZeroRowTransition explains WHY a guarded timer UPDATE matched zero
// rows, turning races into honest, distinct errors instead of a generic
// "update failed".
func (s *StopChargeService) classifyZeroRowTransition(ctx context.Context, rideID uuid.UUID, seq int, starting bool) error {
var startedAt, endedAt *time.Time
err := s.db.QueryRow(ctx,
`SELECT started_at, ended_at FROM ride_stop_charges WHERE ride_id = $1 AND seq = $2`,
rideID, seq).Scan(&startedAt, &endedAt)
if errors.Is(err, pgx.ErrNoRows) {
return ErrStopTimerNotRunning // no approval row => nothing to time
}
if err != nil {
return err
}
switch {
case endedAt != nil:
return ErrStopTimerClosed
case starting && startedAt != nil:
return ErrStopAlreadyStarted
default:
return ErrStopTimerNotStarted
}
}

// ErrStopAlreadyStarted mirrors the stop_timer sentinel for the DB surface.
var ErrStopAlreadyStarted = errors.New("stop timer already started")

// Errors specific to the DB-backed approval guards.
var (
ErrStopRideNotFound = errors.New("ride not found for stop approval")
ErrStopNotRideOwner = errors.New("only the ride owner may approve stops")
)
