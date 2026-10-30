// Package services — NIDAW FARE INTEGRITY (Phase 1): contractual duration.
//
// The agreed billable duration of a booking is derived from the ORIGINAL
// approved route distance and a fixed, versioned minutes-per-kilometre rule —
// never from live traffic, time-of-day speed heuristics, or what the driver
// actually drove. Example: with the v1 rule of 3.0 min/km and a 10 km route,
// the contract duration is exactly 30 minutes even if the trip takes 45 in
// traffic or via a driver-selected detour.
//
// IMPORTANT DISTINCTION (Phase 1 requirement): the minutes-per-kilometre rule
// configured here (MinutesPerKm) is a DURATION rule. It is deliberately a
// separate configuration key from the monetary per-minute rate
// (PerMinuteRate, ETB/minute) used in the fare formula. Reusing the monetary
// rate as a duration multiplier would make fares depend on prices — that bug
// class is what this service exists to prevent.
package services

import (
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

// ============================================================================
// RULE VERSIONS
// ============================================================================

// DurationRuleVersionV1 is the first shipped contractual duration rule:
// a flat 3.0 minutes per kilometre for every ride type. Pinned by name inside
// every fare snapshot so historical rides keep pricing under the rule they
// were quoted with, regardless of later config changes.
const DurationRuleVersionV1 = "v1"

// DefaultDurationRuleVersion is what new bookings freeze when no explicit
// override is configured.
const DefaultDurationRuleVersion = DurationRuleVersionV1

// ErrUnknownDurationRule marks a requested rule version that has no frozen
// definition. Handlers must reject rather than fall back silently — an
// unfrozen duration rule means an unfareable booking.
var ErrUnknownDurationRule = errors.New("unknown contractual duration rule version")

// ErrInvalidContractDistance guards against negative/NaN distances reaching
// the duration math (a data error upstream, never a user-facing clamp).
var ErrInvalidContractDistance = errors.New("contract distance must be finite and non-negative")

// ContractualDurationRule is one immutable version of the minutes-per-km
// policy. MinutesPerKm <= 0 is invalid at construction; there is no free
// duration tier.
type ContractualDurationRule struct {
	Version      string
	MinutesPerKm float64
}

// durationRules is the frozen registry of known rules. Add a NEW version
// constant alongside any policy change; never edit an existing entry's numbers
// in place — snapshots pinned to "v1" must keep computing v1 forever.
var durationRules = map[string]ContractualDurationRule{
	DurationRuleVersionV1: {Version: DurationRuleVersionV1, MinutesPerKm: 3.0},
}

// LookupDurationRule returns the frozen rule for a version string. Unknown
// versions error out (ErrUnknownDurationRule); callers must not substitute a
// default, because silently repricing old bookings under new rules is exactly
// the integrity violation this module prevents.
func LookupDurationRule(version string) (ContractualDurationRule, error) {
	if version == "" {
		version = DefaultDurationRuleVersion
	}
	rule, ok := durationRules[version]
	if !ok {
		return ContractualDurationRule{}, fmt.Errorf("%w: %q", ErrUnknownDurationRule, version)
	}
	return rule, nil
}

// DurationRuleFromEnvironment reads the ACTIVE rule version for new bookings
// from NIDUS_DURATION_RULE_VERSION (defaulting to v1) and validates it exists.
// An env value naming an unknown rule fails loudly at boot rather than being
// ignored — misconfiguration must never quietly reprice riders.
func DurationRuleFromEnvironment() (ContractualDurationRule, error) {
	version := strings.TrimSpace(os.Getenv("NIDUS_DURATION_RULE_VERSION"))
	if version == "" {
		version = DefaultDurationRuleVersion
	}
	return LookupDurationRule(version)
}

// ============================================================================
// CALCULATION
// ============================================================================

// ContractualDuration computes the agreed billable minutes for a frozen
// contract distance under a named rule version:
//
//	Tc = ceil(Dc * MinutesPerKm), floored at 1 minute.
//
// Rounding policy (documented, deterministic): the product Dc*MinutesPerKm is
// rounded UP to the whole minute (ceiling). Ceiling is rider-safe by
// construction here because duration only feeds the FIXED quote — once frozen
// into the snapshot the value never moves again, and rounding up at quote
// time avoids quoting zero minutes for sub-minute trips. A zero-distance
// input still yields 1 minute minimum. NaN/Inf/negative distances are
// rejected, never clamped.
func ContractualDuration(distanceKm float64, ruleVersion string) (minutes int, rule ContractualDurationRule, err error) {
	if math.IsNaN(distanceKm) || math.IsInf(distanceKm, 0) || distanceKm < 0 {
		return 0, ContractualDurationRule{}, ErrInvalidContractDistance
	}
	rule, err = LookupDurationRule(ruleVersion)
	if err != nil {
		return 0, ContractualDurationRule{}, err
	}
	raw := distanceKm * rule.MinutesPerKm
	minutes = int(math.Ceil(raw))
	if minutes < 1 {
		minutes = 1
	}
	return minutes, rule, nil
}

// ContractualDurationForRideType is the extension point for future per-ride
// type duration rules. v1 is flat across all ride types; keeping the ride
// type in the signature now means call sites never change when a v2 rule
// diverges (e.g. shared rides priced on a slower contractual pace).
func ContractualDurationForRideType(distanceKm float64, ruleVersion string, _ RideType) (int, ContractualDurationRule, error) {
	return ContractualDuration(distanceKm, ruleVersion)
}

// FormatDurationMinutes renders "Xh Ym"/"Ym" style text for the rider-facing
// disclosure ("Your fare is based on a contractual duration of ~30 minutes").
// Pure presentation helper; never used in money math.
func FormatDurationMinutes(minutes int) string {
	if minutes < 60 {
		return strconv.Itoa(minutes) + " min"
	}
	return fmt.Sprintf("%dh %dm", minutes/60, minutes%60)
}
