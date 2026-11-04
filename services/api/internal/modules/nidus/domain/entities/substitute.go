package entities

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

// ============================================================================
// DRIVER SUBSTITUTE RELATIONSHIPS (Auth roadmap Phase 7)
//
// A substitute relationship authorizes ONE independent driver account to
// perform explicit operational actions (accepting rides) with ONE vehicle of a
// primary driver's profile. It never transfers wallets, earnings, profiles,
// login credentials, refresh tokens, or biometric state: every operation is
// authorized against the acting user's own identity server-side.
//
// The aggregate mirrors data/migrations/postgres/034_driver_substitutes.sql;
// the status constants below are the exact CHECK-list of that table, so a
// value persisted by the service always satisfies the database constraint.
// ============================================================================

// SubstituteStatus is the lifecycle state of a substitute relationship.
type SubstituteStatus string

const (
	// SubstituteStatusInvited: the primary has minted an invitation; the
	// substitute has not yet proven phone ownership and accepted it. This is
	// the only state carrying a live invite token digest.
	SubstituteStatusInvited SubstituteStatus = "invited"

	// SubstituteStatusPendingSubstituteConfirmation is the transient state
	// between invitation delivery and the substitute's OTP-backed accept.
	// (The accept call itself moves invited -> pending_primary_confirmation;
	// this state exists for flows that separate delivery from acceptance.)
	SubstituteStatusPendingSubstituteConfirmation SubstituteStatus = "pending_substitute_confirmation"

	// SubstituteStatusPendingPrimaryConfirmation: the substitute has accepted
	// with their own verified phone; the primary must now confirm the pairing.
	SubstituteStatusPendingPrimaryConfirmation SubstituteStatus = "pending_primary_confirmation"

	// SubstituteStatusActive: mutual confirmation complete and the
	// substitute's own professional checks passed at activation time.
	SubstituteStatusActive SubstituteStatus = "active"

	// SubstituteStatusExpired is derived at read time once valid_until has
	// passed; authorization checks treat it as terminal-for-authorization.
	SubstituteStatusExpired SubstituteStatus = "expired"

	// SubstituteStatusSuspended temporarily freezes authorization (e.g. a
	// document lapsed mid-relationship); a re-check can restore active.
	SubstituteStatusSuspended SubstituteStatus = "suspended"

	// SubstituteStatusRevoked is the final, irreversible end of a
	// relationship. New invitations may create fresh relationships.
	SubstituteStatusRevoked SubstituteStatus = "revoked"
)

// IsValid reports whether s belongs to the schema CHECK list.
func (s SubstituteStatus) IsValid() bool {
	switch s {
	case SubstituteStatusInvited,
		SubstituteStatusPendingSubstituteConfirmation,
		SubstituteStatusPendingPrimaryConfirmation,
		SubstituteStatusActive,
		SubstituteStatusExpired,
		SubstituteStatusSuspended,
		SubstituteStatusRevoked:
		return true
	}
	return false
}

// IsLive reports whether the relationship still occupies the unique "live"
// slot per (primary, substitute, vehicle). Expired/suspended/revoked rows do
// not block a fresh invitation for the same triple.
func (s SubstituteStatus) IsLive() bool {
	switch s {
	case SubstituteStatusInvited,
		SubstituteStatusPendingSubstituteConfirmation,
		SubstituteStatusPendingPrimaryConfirmation,
		SubstituteStatusActive:
		return true
	}
	return false
}

// CanAuthorize reports whether the status can grant operational permissions
// at all. Expiry/validity windows are enforced separately by IsAuthorizedAt;
// suspended/revoked/expired never authorize.
func (s SubstituteStatus) CanAuthorize() bool {
	return s == SubstituteStatusActive
}

// substituteTransitions is the authoritative status machine. Only these edges
// are legal; everything else (including self-transitions and any edge out of
// revoked) is rejected. 'expired' is written by the expiry sweep, 'suspended'
// by suspend, 'revoked' by revoke — matching the service's write paths.
var substituteTransitions = map[SubstituteStatus][]SubstituteStatus{
	SubstituteStatusInvited: {
		SubstituteStatusPendingSubstituteConfirmation, // delivery acknowledged
		SubstituteStatusPendingPrimaryConfirmation,    // substitute accepted via OTP+token
		SubstituteStatusRevoked,                       // primary withdrew the invite
		SubstituteStatusExpired,                       // invite window lapsed
	},
	SubstituteStatusPendingSubstituteConfirmation: {
		SubstituteStatusPendingPrimaryConfirmation, // substitute accepted
		SubstituteStatusRevoked,                    // primary withdrew
		SubstituteStatusExpired,                    // invite window lapsed
	},
	SubstituteStatusPendingPrimaryConfirmation: {
		SubstituteStatusActive,    // primary confirmed + gating passed
		SubstituteStatusRevoked,   // primary declined (never reopens the invite)
		SubstituteStatusExpired,   // validity window lapsed pre-activation
	},
	SubstituteStatusActive: {
		SubstituteStatusSuspended, // temporary freeze (document lapse, safety hold)
		SubstituteStatusRevoked,   // permanent end
		SubstituteStatusExpired,   // valid_until passed
	},
	SubstituteStatusSuspended: {
		SubstituteStatusActive,  // re-authorized after checks pass again
		SubstituteStatusRevoked, // decision escalated to permanent
		SubstituteStatusExpired, // valid_until passed while suspended
	},
	SubstituteStatusExpired: {},
	SubstituteStatusRevoked: {},
}

// ErrInvalidSubstituteTransition signals a rejected status edge.
var ErrInvalidSubstituteTransition = errors.New("invalid substitute relationship status transition")

// CanTransitionTo reports whether moving from s to next is legal.
func (s SubstituteStatus) CanTransitionTo(next SubstituteStatus) bool {
	targets, ok := substituteTransitions[s]
	if !ok {
		return false
	}
	for _, t := range targets {
		if t == next {
			return true
		}
	}
	return false
}

// NOTE: the PendingPrimaryConfirmation -> Invited edge listed above would let
// a decline silently reopen a consumed invitation; the machine forbids it.
// Declines go straight to Revoked (see service.DeclineByPrimary).

// ============================================================================
// PERMISSIONS
// ============================================================================

// SubstitutePermission enumerates the explicit operational grants a
// relationship can carry. Unknown permission strings are rejected at the
// boundary; there is no wildcard grant.
type SubstitutePermission string

const (
	// SubPermAcceptRides lets the substitute receive and act on dispatch
	// offers scoped to the relationship's primary/vehicle.
	SubPermAcceptRides SubstitutePermission = "accept_rides"
)

// IsValid reports whether p is a sanctioned permission.
func (p SubstitutePermission) IsValid() bool {
	return p == SubPermAcceptRides
}

// ValidateSubstitutePermissions normalizes and validates a permission set:
// rejects empty sets, unknown values, and duplicates. Returns the canonical
// slice in input order (deduplicated nothing — duplicates are an error so
// clients cannot smuggle repeated grants past audit).
func ValidateSubstitutePermissions(in []SubstitutePermission) ([]SubstitutePermission, error) {
	if len(in) == 0 {
		return nil, errors.New("substitute relationship requires at least one permission")
	}
	seen := make(map[SubstitutePermission]struct{}, len(in))
	out := make([]SubstitutePermission, 0, len(in))
	for _, p := range in {
		if !p.IsValid() {
			return nil, errors.New("unknown substitute permission: " + string(p))
		}
		if _, dup := seen[p]; dup {
			return nil, errors.New("duplicate substitute permission: " + string(p))
		}
		seen[p] = struct{}{}
		out = append(out, p)
	}
	return out, nil
}

// HasPermission reports whether the granted set contains p.
func HasPermission(granted []SubstitutePermission, p SubstitutePermission) bool {
	for _, g := range granted {
		if g == p {
			return true
		}
	}
	return false
}

// ============================================================================
// AGGREGATE
// ============================================================================

// SubstituteRelationship is the lightweight server-side record associating a
// primary driver, an independent substitute user, one vehicle label, explicit
// permissions, mutual confirmations, and validity windows. Field names mirror
// the 034 table columns.
type SubstituteRelationship struct {
	ID            uuid.UUID
	PrimaryDriver uuid.UUID // drivers.id
	SubstituteUser uuid.UUID // users.id — the substitute acts under THIS account

	VehicleLabel *string // NULL => "no specific vehicle"
	Permissions  []SubstitutePermission
	Status       SubstituteStatus

	// Invitation security: raw token is never stored, only its SHA-256
	// digest, and only while status == invited.
	InviteTokenHash string     // "" when absent/consumed
	InviteExpiresAt *time.Time // single-use window of the invitation itself

	AcceptedBySubstituteAt *time.Time
	ConfirmedByPrimaryAt   *time.Time
	ActivatedAt            *time.Time

	ValidFrom  *time.Time
	ValidUntil *time.Time

	RevokedAt    *time.Time
	RevokeReason *string

	CreatedAt time.Time
	UpdatedAt time.Time
}

// EffectiveStatus applies the read-time expiry derivation: an otherwise-live
// relationship whose valid_until has passed behaves as expired. Invite-stage
// rows expire via invite_expires_at instead (the validity window starts at
// activation), so the two rules never conflict.
func (sr *SubstituteRelationship) EffectiveStatus(now time.Time) SubstituteStatus {
	if sr == nil {
		return SubstituteStatusRevoked
	}
	switch sr.Status {
	case SubstituteStatusInvited, SubstituteStatusPendingSubstituteConfirmation:
		if sr.InviteExpiresAt != nil && now.After(*sr.InviteExpiresAt) {
			return SubstituteStatusExpired
		}
	case SubstituteStatusPendingPrimaryConfirmation, SubstituteStatusActive:
		if sr.ValidUntil != nil && now.After(*sr.ValidUntil) {
			return SubstituteStatusExpired
		}
	}
	return sr.Status
}

// IsAuthorizedAt reports whether this relationship grants operational
// authority to SubstituteUser at time t: the status must be active (after
// read-time expiry derivation), the validity window must contain t, and the
// requested permission must be explicitly granted. Accept_rides is required
// for dispatch participation; callers pass the permission they need.
func (sr *SubstituteRelationship) IsAuthorizedAt(t time.Time, perm SubstitutePermission) bool {
	if sr == nil || !sr.Status.CanAuthorize() {
		return false
	}
	if sr.EffectiveStatus(t) != SubstituteStatusActive {
		return false
	}
	if sr.ValidFrom != nil && t.Before(*sr.ValidFrom) {
		return false
	}
	if sr.ValidUntil != nil && t.After(*sr.ValidUntil) {
		return false
	}
	return HasPermission(sr.Permissions, perm)
}

// InviteStillRedeemable reports whether an invitation token can still be
// spent: only invite-stage statuses carry a live digest within their window.
func (sr *SubstituteRelationship) InviteStillRedeemable(now time.Time) bool {
	if sr == nil {
		return false
	}
	if sr.Status != SubstituteStatusInvited && sr.Status != SubstituteStatusPendingSubstituteConfirmation {
		return false
	}
	if sr.InviteTokenHash == "" {
		return false
	}
	if sr.InviteExpiresAt != nil && now.After(*sr.InviteExpiresAt) {
		return false
	}
	return true
}
