// Package entities — NIDAW FARE INTEGRITY (Phase 2): rider-approved stop
// charges.
//
// A stop becomes part of the PRICING CONTRACT only after the rider explicitly
// approves its disclosed fee. This file encodes the platform's transparent,
// pre-agreed stoppage policy as pure domain rules with no I/O:
//
//   - Every approved stop carries a FIXED, visible additional fare
//     (StopFeeSantim), frozen from the pricing config at approval time.
//   - A short stop (under StopWaitingThresholdMinutes) incurs ONLY that fixed
//     fee.
//   - A stop whose server-recorded timer reaches the threshold (10 minutes)
//     additionally incurs a waiting charge equal to 50% of the ORIGINAL
//     BOOKING FARE (the frozen quoted total) — never a fare that already
//     includes other stop fees or waiting charges. That base choice is what
//     makes the policy non-compounding: two long stops cost exactly 2×(fee +
//     50%·F0), not an escalating series computed on inflated bases.
//   - Amounts are integer ETB santim with deterministic half-up rounding at
//     the single float boundary (50% of an odd santim total rounds up one
//     santim in the rider's disclosed favor being impossible — see
//     ComputeWaitingChargeSantim for the exact rule).
package entities

import (
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
)

// ============================================================================
// POLICY CONSTANTS (version v1 — mirrored by migration 028 comments and docs)
// ============================================================================

const (
	// StopPolicyVersion names this stoppage-pricing policy so persisted rows
	// and tests can pin which rule set produced a charge. Future policy edits
	// add a NEW version; historical rows keep theirs.
	StopPolicyVersion = "stops-v1"

	// StopFeeSantimDefaultV1 is the fixed per-stop additional fare under
	// policy v1: Br 10.00 = 1000 santim. Overridable via
	// NIDUS_STOP_FEE_SANTIM at deploy time; frozen per-approval onto the row
	// so later config changes never rewrite history.
	StopFeeSantimDefaultV1 int64 = 1000

	// StopWaitingThresholdMinutes is the dwell duration at (or beyond) which
	// a stop crosses from "short stop, fixed fee only" into waiting-charge
	// territory. Exactly 10 minutes triggers ("lasting 10 minutes or longer").
	StopWaitingThresholdMinutes = 10

	// StopWaitingChargeNumerator / DenominatorV1 express the waiting charge as
	// an exact ratio of the ORIGINAL booking fare: 50% = 1/2. Using a rational
	// pair keeps the rule auditable and unit-testable without float drift.
	StopWaitingChargeNumeratorV1   = 1
	StopWaitingChargeDenominatorV1 = 2
)

// Errors surfaced by stop-charge validation. All are stable codes the HTTP
// layer maps verbatim.
var (
	// ErrStopNotApproved: a charge request against a stop the rider never
	// accepted. The platform must NEVER add an unapproved stop charge —
	// this guard is the gate.
	ErrStopNotApproved = errors.New("stop charge requires explicit rider approval")

	// ErrStopAlreadyApproved: approvals are exactly-once per stop sequence.
	// Re-approving (double-tap, retry storm) must not double the fee.
	ErrStopAlreadyApproved = errors.New("stop already approved")

	// ErrStopSeqOutOfRange references a stop that does not exist on the ride.
	ErrStopSeqOutOfRange = errors.New("stop sequence is out of range for this ride")

	// ErrNegativeSantim rejects tampered amounts; a stop charge is never a
	// credit.
	ErrNegativeSantim = errors.New("stop charge amounts must be non-negative")

	// ErrStopTimerNotRunning means a completion was attempted without a
	// matching server-side start — drivers cannot fabricate or backdate a
	// stop window.
	ErrStopTimerNotRunning = errors.New("stop timer is not running")

	// ErrStopTimerAlreadyStopped closes the double-stop race: the first
	// recorded end wins and later attempts are rejected (not silently
	// merged), so the dwell duration used for money math is unique.
	ErrStopTimerAlreadyStopped = errors.New("stop timer already stopped")
)

// ============================================================================
// APPROVED STOP CHARGE
// ============================================================================

// StopCharge is the persisted record of ONE rider-approved intermediate stop
// and everything the settlement contract needs about it: the disclosed fixed
// fee, the server-measured dwell, and the waiting charge the dwell earned (if
// any). Seq matches ride_stops.seq (1-based, visit order).
type StopCharge struct {
	RideID uuid.UUID
	Seq    int

	// Fixed fee shown to and approved by the rider BEFORE the stop became
	// payable. Frozen at approval; policy version records which rule minted
	// it.
	StopFeeSantim   int64
	StopPolicyVer   string
	ApprovedByRider bool
	ApprovedAt      *time.Time

	// Server-measured dwell (auditable stop events; zero until stopped).
	// TimerStartedAt / TimerEndedAt are the server-clock stop-window events:
	// nil until the driver starts/stops the timer for this stop.
	DurationMin    int
	TimerStartedAt *time.Time
	TimerEndedAt   *time.Time
	WaitingEligible bool

	// Waiting charge earned by crossing the threshold, computed EXCLUSIVELY
	// from the original booking fare (non-compounding). Zero when the stop
	// stayed short.
	WaitingChargeSantim int64
}

// TotalSantim is the stop's full contribution to the payable amount.
func (c StopCharge) TotalSantim() int64 { return c.StopFeeSantim + c.WaitingChargeSantim }

// Validate enforces the invariants the persistence layer and settlement both
// rely on: approved-only charges, non-negative santim, known policy version.
func (c StopCharge) Validate() error {
	if !c.ApprovedByRider {
		return ErrStopNotApproved
	}
	if c.Seq < 1 || c.Seq > MaxRideStops {
		return ErrStopSeqOutOfRange
	}
	if c.StopFeeSantim < 0 || c.WaitingChargeSantim < 0 {
		return ErrNegativeSantim
	}
	if c.StopPolicyVer != StopPolicyVersion {
		return errors.New("unknown stop policy version " + c.StopPolicyVer)
	}
	return nil
}

// ============================================================================
// PURE POLICY FUNCTIONS
// ============================================================================

// CrossesWaitingThreshold reports whether a dwell of durationMin minutes
// reaches the 10-minute waiting threshold. Boundary inclusive: exactly 10
// minutes IS "lasting 10 minutes or longer". Negative durations (clock skew
// clamped upstream) never trigger.
func CrossesWaitingThreshold(durationMin int) bool {
	return durationMin >= StopWaitingThresholdMinutes
}

// ComputeWaitingChargeSantim returns the waiting charge for a threshold-
// crossing stop given the ORIGINAL frozen booking fare F0 (quoted total in
// santim). The charge is exactly 50% of F0 — computed on the booking fare
// alone, never on gross fares that already include other stops' fees or
// waiting charges, which is what guarantees non-compounding across multiple
// long stops. Rounding: half-up to the nearest santim (odd santim totals gain
// one santim; deterministic and identical on every platform). Zero-and-
// negative booking fares are rejected as tampering (returns 0; callers treat
// F0<=0 as a data error before ever calling here).
func ComputeWaitingChargeSantim(originalBookingFareSantim int64) int64 {
	if originalBookingFareSantim <= 0 {
		return 0
	}
	charge := float64(originalBookingFareSantim) *
		float64(StopWaitingChargeNumeratorV1) /
		float64(StopWaitingChargeDenominatorV1)
	return int64(math.Round(charge)) // half-up, deterministic
}

// StopChargeFor computes the full payable contribution of one approved stop
// from its measured dwell and the original booking fare. Short stops earn
// only the fixed fee; threshold-crossing stops earn fee + waiting charge.
// This is the single function both the live UI preview and the settlement
// finalizer call, so "what the rider saw" and "what the rider pays" are the
// same code path.
func StopChargeFor(approvedFeeSantim int64, durationMin int, originalBookingFareSantim int64) (fee int64, waiting int64) {
	if approvedFeeSantim < 0 || originalBookingFareSantim < 0 {
		return 0, 0
	}
	if !CrossesWaitingThreshold(durationMin) {
		return approvedFeeSantim, 0
	}
	return approvedFeeSantim, ComputeWaitingChargeSantim(originalBookingFareSantim)
}
