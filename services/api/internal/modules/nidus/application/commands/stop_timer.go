// Package commands — NIDAW FARE INTEGRITY (Phase 2): server-authoritative
// stop timing.
//
// The waiting-charge policy ("a stop lasting 10 minutes or longer incurs an
// additional charge equal to 50% of the original booking fare") is only fair
// if the CLOCK is not in anyone's pocket. This file owns that clock:
//
//   - Start/stop timestamps are written exclusively by the API server
//     (time.Now().UTC() inside the same transaction as the row update). No
//     client-supplied time ever enters money math.
//   - A timer can only start on a stop the RIDER APPROVED (ride_stop_charges
//     row exists). Drivers cannot unilaterally create a rider-requested stop,
//     and arriving at an unapproved waypoint starts nothing — so no dwell can
//     silently earn a charge.
//   - Double-start and double-stop races resolve via guarded UPDATEs
//     (started_at IS NULL / ended_at IS NULL in the WHERE clause): exactly
//     one transition wins, later attempts fail with stable sentinels instead
//     of rewriting history.
//   - Duration is truncated DOWN to whole minutes (floor), which is strictly
//     rider-favorable: 9m59s never crosses the 10-minute threshold; and the
//     threshold comparison itself lives in the domain layer
//     (entities.CrossesWaitingThreshold) so preview and settlement share one
//     rule.
//   - Clock-skew safety: a measured end-before-start clamps to 0 minutes
//     rather than producing negative durations or spurious charges.
package commands

import (
	"errors"
	"fmt"
	"time"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

// ============================================================================
// STOP TIMER CONTRACT
// ============================================================================

// StopTimerState is the auditable snapshot of one stop's server-recorded
// window. It is what GET surfaces expose and what the approval handler
// previews; it carries no mutable authority itself — every field derives from
// persisted server-clock events.
type StopTimerState struct {
	RideID    uuidType
	Seq       int
	Approved  bool
	StartedAt *time.Time
	EndedAt   *time.Time
	// Running is true between StartedAt and EndedAt.
	Running bool
	// DurationMin is the finalized whole-minute dwell (floor), valid only once
	// EndedAt is set; while running it reports the elapsed-so-far preview,
	// which is display-only and NEVER payable until the stop is closed.
	DurationMin int
	// WaitingEligible reports whether the finalized dwell crossed the
	// threshold. False while the timer is still running.
	WaitingEligible bool
}

// Errors for timer transitions. Stable sentinels; the HTTP layer maps them to
// codes without re-matching strings.
var (
	// ErrStopTimerNotApproved wraps entities.ErrStopNotApproved for the timer
	// surface: starting a timer against a stop the rider never approved is
	// refused before any timestamp is taken.
	ErrStopTimerNotApproved = errors.New("cannot time an unapproved stop")

	// ErrStopTimerAlreadyStarted rejects a second start on the same stop
	// (guarded by started_at IS NULL in SQL; declared here for the pure
	// state-machine helper below, which tests exercise without a database).
	ErrStopTimerAlreadyStarted = errors.New("stop timer already started")

	// ErrStopTimerNotRunning rejects stopping a timer that was never started
	// or already closed — drivers cannot fabricate a dwell window after the
	// fact.
	ErrStopTimerNotRunning = errors.New("stop timer is not running")

	// ErrStopTimerClosed accepts nothing further: once closed, the finalized
	// duration is immutable (corrections require operator action outside this
	// contract, never silent rewrites).
	ErrStopTimerClosed = errors.New("stop timer already closed")
)

// ============================================================================
// PURE STATE MACHINE (no I/O — unit-testable determinism core)
// ============================================================================

// StopTimerTransition computes the next timer state from the current one plus
// a SERVER-CLOCK event time. Handlers call this before persisting so the
// decision logic and the audit trail can never diverge. All returned times
// are UTC-normalized copies of serverNow; caller-supplied "event times" do
// not exist in this API by design.
func StopTimerTransition(cur StopTimerState, action string, serverNow time.Time) (StopTimerState, error) {
	if !cur.Approved {
		return cur, ErrStopTimerNotApproved
	}
	now := serverNow.UTC()

	switch action {
	case "start":
		if cur.StartedAt != nil {
			return cur, ErrStopTimerAlreadyStarted
		}
		next := cur
		next.StartedAt = &now
		next.Running = true
		next.DurationMin = 0
		return next, nil

	case "stop":
		if cur.StartedAt == nil {
			return cur, ErrStopTimerNotRunning
		}
		if cur.EndedAt != nil {
			return cur, ErrStopTimerClosed
		}
		next := cur
		next.EndedAt = &now
		next.Running = false
		dwell := now.Sub(*next.StartedAt)
		if dwell < 0 {
			// Server clocks are monotonic within one process, but replicas
			// can disagree at the edges. Clamp: never mint negative time,
			// never mint a charge from skew.
			dwell = 0
		}
		next.DurationMin = int(dwell.Minutes()) // floor — rider-favorable
		next.WaitingEligible = entities.CrossesWaitingThreshold(next.DurationMin)
		return next, nil

	default:
		return cur, fmt.Errorf("unknown stop timer action %q", action)
	}
}

// PreviewWaitingChargeSantim answers the rider's "what will this cost me?"
// question BEFORE they approve a change: given the disclosed fixed fee, a
// hypothetical dwell crossing the threshold, and the ORIGINAL frozen booking
// fare F0, return the exact amounts the platform would add. UI text must be
// generated from these numbers, never hand-computed client-side.
func PreviewWaitingChargeSantim(originalBookingFareSantim int64) (fee int64, waiting int64, thresholdMin int) {
	waiting = entities.ComputeWaitingChargeSantim(originalBookingFareSantim)
	return StopFeeSantimV1(), waiting, entities.StopWaitingThresholdMinutes
}
