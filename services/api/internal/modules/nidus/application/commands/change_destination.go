// Package commands — §3.5 mid-trip destination change, FARE INTEGRITY
// (Phase 2) contract-aligned revision.
//
// ChangeDestinationHandler lets the rider replace the dropoff of a ride that
// is already matched/en-route or in progress. The recomputed fare comes from
// the SAME pricing service used at request time (multi-leg over the current
// waypoint chain), so the number shown in the rider's confirmation sheet is
// the number they pay — no client-side heuristics, per Global Rule 1.
//
// CONTRACT MODEL (§2.1 immutability end-to-end):
//
//   - The accepted booking snapshot is NEVER edited. A rider-approved
//     destination change is an APPROVED AMENDMENT: the new quote is frozen as
//     a NEW immutable fare-snapshot revision keyed "amend:<ride_id>:<n>" and
//     persisted to destination_fare_amendments (migration 030).
//     rides.fare_snapshot_id is repointed to the amendment id inside the same
//     race-guarded UPDATE, so completion and settlement always read THE
//     current contract through exactly one pointer — requireContract's
//     fare_amount ↔ quoted_total_santim reconciliation applies unchanged.
//   - Amendment persistence is fail-closed. If the amended contract row cannot
//     be written durably, the ride row is not touched either: a changed
//     dropoff without a stored contract would re-open exactly the "surprise
//     at trip completion" failure mode §2.4/§2.5 forbid.
//   - Idempotency: seq = count(existing amendments)+1 with UNIQUE(ride_id,
//     seq); a retried confirmation whose coordinates match the latest stored
//     amendment replays that amendment's numbers instead of minting a second
//     revision for the same intent.
//
// Other invariants (unchanged):
//   - Rider-only: the authenticated user must own the ride (ErrForbidden).
//   - State gate: entities.Ride.CanChangeDestination() — driver_en_route or
//     in_progress only; requested/searching and terminal states are rejected
//     with ErrDestinationNotChangeable.
//   - Concurrency: the UPDATE is race-guarded on (status, old dropoff coords,
//     expected contract pointer) so a simultaneous complete/cancel wins
//     cleanly and this handler returns ErrDestinationNotChangeable instead of
//     clobbering terminal state.
//   - Stops are preserved verbatim: changing the dropoff never silently drops
//     intermediate waypoints; the new fare prices pickup → stops → NEW dropoff.
//   - Event: ride.destination_changed is published AFTER durable persistence,
//     carrying previous and new fares so downstream surfaces (driver relay,
//     notifications) never recompute money themselves.
package commands

import (
	"context"
	"errors"
	"fmt"
	"time"

	"nidaw-backend/internal/modules/nidus/application/services"
	nidusevents "nidaw-backend/internal/modules/nidus/domain/events"
	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/eventbus"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ChangeDestinationCommand is the rider-intent DTO for one mid-trip dropoff
// replacement. Address is the human-readable label resolved by the client's
// autocomplete/reverse-geocode step; empty address is tolerated (coordinates
// remain authoritative) but never fabricated server-side. There is
// deliberately no fare field: money comes exclusively from the pricing
// service and the frozen amendment revision.
type ChangeDestinationCommand struct {
	RideID      uuid.UUID
	UserID      uuid.UUID // authenticated rider subject (JWT)
	DropoffLat  float64
	DropoffLng  float64
	DropoffAddr string
}

// ChangeDestinationResult carries the authoritative before/after money so the
// confirmation UI can show the real fare delta. Values are currency units
// (not santim) to match FareAmount semantics elsewhere; the exact integer
// santim figures live on the persisted amendment revision.
type ChangeDestinationResult struct {
	RideID       uuid.UUID `json:"ride_id"`
	PreviousFare float64   `json:"previous_fare"`
	NewFare      float64   `json:"new_fare"`
	Currency     string    `json:"currency"`
	DistanceKm   float64   `json:"distance_km"`

	// Amendment contract identity (Phase 2): which approved revision now owns
	// the payable amount. Amended=false marks a replay of the newest stored
	// revision — "nothing changed since your last view".
	AmendmentID  string `json:"amendment_id,omitempty"`
	AmendmentSeq int    `json:"amendment_seq,omitempty"`
	Amended      bool   `json:"amended"`
}

// ChangeDestinationHandler implements the §3.5 PATCH /rides/{id}/destination
// use case. It embeds lifecycleBase to reuse loadRide (unknown id →
// ErrRideNotFound, honest 404 without leaking existence details).
type ChangeDestinationHandler struct {
	lifecycleBase
	pricingService *services.PricingService
}

// NewChangeDestinationHandler wires the command with its collaborators.
// pricingService must not be nil: a destination change without repricing
// would persist an inconsistent fare, which is exactly the class of bug
// Global Rule 1 forbids. A nil service fails loudly on first Execute rather
// than silently skipping the money recomputation.
func NewChangeDestinationHandler(db *database.Postgres, eventBus eventbus.EventBus, pricingService *services.PricingService) *ChangeDestinationHandler {
	return &ChangeDestinationHandler{
		lifecycleBase:  lifecycleBase{db: db, eventBus: eventBus},
		pricingService: pricingService,
	}
}

// Execute performs the destination change as an approved contract amendment.
// See file header for invariants.
func (h *ChangeDestinationHandler) Execute(ctx context.Context, cmd ChangeDestinationCommand) (*ChangeDestinationResult, error) {
	if h.pricingService == nil {
		return nil, fmt.Errorf("%w: pricing service not configured", ErrFareCalcFailed)
	}

	ride, err := h.loadRide(ctx, cmd.RideID)
	if err != nil {
		return nil, err
	}

	// Rider authorization: only the requesting user may amend the route.
	// Drivers get route updates via the published domain event, never here.
	if ride.UserID != cmd.UserID {
		return nil, ErrForbidden
	}

	if !ride.CanChangeDestination() {
		return nil, ErrDestinationNotChangeable
	}

	// --- Current contract ------------------------------------------------------
	// Amendments chain onto the CURRENT frozen quote. No contract => nothing
	// transparent to amend => fail closed, mirroring the stop-approval rule
	// (ErrApproveStopNoContract): we never invent money at amendment time.
	var curQuotedSantim int64
	var curCurrency string
	err = h.db.QueryRow(ctx, `
		SELECT quoted_total_santim, currency FROM ride_fare_snapshots WHERE ride_id = $1`,
		cmd.RideID).Scan(&curQuotedSantim, &curCurrency)
	if err != nil {
		return nil, fmt.Errorf("%w: ride %s has no frozen fare contract to amend: %v",
			ErrFareCalcFailed, cmd.RideID, err)
	}
	if curCurrency != entities.CurrencyETB {
		return nil, fmt.Errorf("%w: contract currency %q is not ETB", ErrFareCalcFailed, curCurrency)
	}

	// --- Idempotent replay -----------------------------------------------------
	// If the newest stored amendment already describes THIS exact dropoff, a
	// retried confirmation replays its numbers rather than minting revision
	// n+1 for the same intent.
	replayed, err := h.latestAmendment(ctx, cmd.RideID, cmd.DropoffLat, cmd.DropoffLng)
	if err != nil {
		return nil, err
	}
	if replayed != nil {
		return &ChangeDestinationResult{
			RideID:       ride.ID,
			PreviousFare: float64(curQuotedSantim) / 100.0,
			NewFare:      replayed.newFare,
			Currency:     entities.CurrencyETB,
			DistanceKm:   replayed.distanceKm,
			AmendmentID:  replayed.id.String(),
			AmendmentSeq: replayed.seq,
			Amended:      false,
		}, nil
	}

	// --- Reprice over the FULL current chain ------------------------------------
	// [pickup, existing stops..., NEW dropoff]. Existing stops are carried
	// through untouched; contractual duration is re-derived from the amended
	// route distance via the versioned minutes-per-km rule (never actuals).
	chainStops := make([]services.Waypoint, 0, len(ride.Stops)+1)
	for _, s := range ride.Stops {
		chainStops = append(chainStops, services.Waypoint{Lat: s.Lat, Lng: s.Lng})
	}
	chainStops = append(chainStops, services.Waypoint{Lat: cmd.DropoffLat, Lng: cmd.DropoffLng})

	estimate, err := h.pricingService.CalculateFareWithStops(ctx, ride.PickupLat, ride.PickupLng, chainStops, services.RideType(ride.RideType))
	if err != nil {
		return nil, err
	}
	if estimate.Currency != entities.CurrencyETB {
		return nil, fmt.Errorf("%w: amended quote currency %q is not ETB", ErrFareCalcFailed, estimate.Currency)
	}
	newFareSantim := estimate.TotalFare
	newFare := float64(newFareSantim) / 100.0
	prevFare := float64(curQuotedSantim) / 100.0

	// Deterministic component reconciliation identical to SnapshotFromEstimate:
	// gross equals the pre-floor sum when no minimum-fare uplift applied,
	// otherwise gross equals the floor exactly. Anything else means the quote
	// engine drifted from the contract rules — refuse the amendment.
	sum := estimate.BaseFare + estimate.DistanceFare + estimate.TimeFare + estimate.SurgeAmount
	switch {
	case newFareSantim < sum:
		return nil, fmt.Errorf("%w: amended gross %d below component sum %d", ErrFareCalcFailed, newFareSantim, sum)
	case sum >= estimate.MinimumFare && newFareSantim != sum:
		return nil, fmt.Errorf("%w: amended gross %d != component sum %d (no floor applied)", ErrFareCalcFailed, newFareSantim, sum)
	case sum < estimate.MinimumFare && newFareSantim != estimate.MinimumFare:
		return nil, fmt.Errorf("%w: amended gross %d != minimum fare %d (floor applied)", ErrFareCalcFailed, newFareSantim, estimate.MinimumFare)
	}

	// --- Freeze the amendment revision -------------------------------------------
	amendID := uuid.New()
	seq, err := h.nextAmendmentSeq(ctx, cmd.RideID)
	if err != nil {
		return nil, err
	}
	key := fmt.Sprintf("amend:%s:%d", cmd.RideID.String(), seq)
	frozenAt := estimate.CalculatedAt.UTC()
	if frozenAt.IsZero() {
		frozenAt = time.Now().UTC()
	}
	perKm, perMin := h.pricingService.RatesForRideType(services.RideType(ride.RideType))

	_, err = h.db.Exec(ctx, `
		INSERT INTO destination_fare_amendments (
			id, ride_id, idempotency_key, seq,
			prev_dropoff_lat, prev_dropoff_lng, dropoff_lat, dropoff_lng, dropoff_address,
			contract_distance_km, contract_duration_min,
			base_fare_santim, distance_fare_santim, time_fare_santim,
			surge_amount_santim, minimum_fare_santim, gross_fare_santim,
			quoted_total_santim,
			ride_type, distance_rate_per_km, time_rate_per_minute,
			surge_multiplier, surge_reason, minutes_per_km,
			pricing_config_version, duration_rule_version,
			currency, approved_by, previous_quoted_santim, approved_at
		) VALUES (
			$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30
		)
		ON CONFLICT (idempotency_key) DO NOTHING`,
		amendID, cmd.RideID, key, seq,
		ride.DropoffLat, ride.DropoffLng, cmd.DropoffLat, cmd.DropoffLng, nullString(cmd.DropoffAddr),
		estimate.DistanceKm, estimate.DurationMinutes,
		estimate.BaseFare, estimate.DistanceFare, estimate.TimeFare,
		estimate.SurgeAmount, estimate.MinimumFare, estimate.TotalFare,
		estimate.TotalFare,
		string(estimate.RideType), perKm, perMin,
		estimate.SurgeMultiplier, nullString(estimate.SurgeReason), estimate.MinutesPerKm,
		estimate.ConfigVersion, estimate.DurationRuleVersion,
		entities.CurrencyETB, cmd.UserID, curQuotedSantim, frozenAt,
	)
	if err != nil {
		// Fail closed: no ride-row mutation when the amended contract could not
		// be persisted durably.
		return nil, fmt.Errorf("%w: could not freeze amended fare contract: %v", ErrFareCalcFailed, err)
	}

	// --- Race-guarded pointer + geometry update ----------------------------------
	// Pins status, the exact OLD dropoff coordinates AND the contract row we
	// amended from. If a concurrent CompleteRide/CancelRide moved the ride, or
	// another change already landed, RowsAffected is 0: delete our just
	// inserted revision (nothing references it yet — rides still points at the
	// previous contract) and refuse honestly.
	tag, err := h.db.Exec(ctx, `
		UPDATE rides
		   SET dropoff_lat = $2, dropoff_lng = $3,
		       dropoff_address = COALESCE(NULLIF($4, ''), dropoff_address),
		       fare_amount = $5, currency = $6,
		       distance_km = $7, duration_minutes = $8,
		       fare_snapshot_id = $9,
		       updated_at = NOW()
		 WHERE id = $1
		   AND status IN ('driver_en_route', 'in_progress')
		   AND dropoff_lat = $10 AND dropoff_lng = $11
		   AND fare_snapshot_id IS NOT DISTINCT FROM $12`,
		cmd.RideID, cmd.DropoffLat, cmd.DropoffLng, cmd.DropoffAddr,
		newFare, entities.CurrencyETB,
		estimate.DistanceKm, estimate.DurationMinutes,
		amendID,
		ride.DropoffLat, ride.DropoffLng, ride.FareSnapshotID,
	)
	if err != nil {
		h.compensateAmendment(ctx, amendID)
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		// Lost the race against a transition or a parallel change. Remove the
		// orphan revision so the amendment sequence stays gap-free for audit,
		// and reject — nothing about the ride changed.
		h.compensateAmendment(ctx, amendID)
		return nil, ErrDestinationNotChangeable
	}

	// --- Announce (durable persistence happened first) ----------------------------
	ev := &nidusevents.RideDestinationChanged{
		RideID:       ride.ID,
		UserID:       ride.UserID,
		DriverID:     ride.DriverID,
		OldDropLat:   ride.DropoffLat,
		OldDropLng:   ride.DropoffLng,
		NewDropLat:   cmd.DropoffLat,
		NewDropLng:   cmd.DropoffLng,
		NewAddress:   cmd.DropoffAddr,
		PreviousFare: prevFare,
		NewFare:      newFare,
		Currency:     entities.CurrencyETB,
	}
	if err := h.publishDomainEvent(ctx, ev.ToEvent()); err != nil {
		// The amendment itself succeeded durably; a publish failure degrades
		// delivery of the live update (WS/notifications retry paths exist
		// downstream), it does NOT roll back the contract. Swallow-and-succeed
		// is deliberate: rolling back would diverge DB vs what the rider
		// already sees confirmed. Ride state remains readable via GET
		// /rides/:id, so no information is lost — only the push latency.
		_ = err
	}

	return &ChangeDestinationResult{
		RideID:        ride.ID,
		PreviousFare:  prevFare,
		NewFare:       newFare,
		Currency:      entities.CurrencyETB,
		DistanceKm:    estimate.DistanceKm,
		AmendmentID:   amendID.String(),
		AmendmentSeq:  seq,
		Amended:       true,
	}, nil
}

// ============================================================================
// INTERNALS
// ============================================================================

type storedAmendment struct {
	id         uuid.UUID
	seq        int
	newFare    float64
	distanceKm float64
}

// latestAmendment returns the ride's highest-seq amendment when it already
// matches the requested dropoff coordinates exactly — the idempotent-replay
// path for double-tapped confirmations. Returns (nil, nil) when there is no
// matching stored revision.
func (h *ChangeDestinationHandler) latestAmendment(ctx context.Context, rideID uuid.UUID, lat, lng float64) (*storedAmendment, error) {
	var a storedAmendment
	var fareSantim int64
	err := h.db.QueryRow(ctx, `
		SELECT id, seq, quoted_total_santim, contract_distance_km
		  FROM destination_fare_amendments
		 WHERE ride_id = $1 AND dropoff_lat = $2 AND dropoff_lng = $3
		 ORDER BY seq DESC LIMIT 1`,
		rideID, lat, lng).
		Scan(&a.id, &a.seq, &fareSantim, &a.distanceKm)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("lookup destination amendment replay: %w", err)
	}
	a.newFare = float64(fareSantim) / 100.0
	return &a, nil
}

// nextAmendmentSeq derives the amendment revision number from the persisted
// history (original booking snapshot counts as revision 0).
// UNIQUE(ride_id, seq) serializes concurrent changes: exactly one INSERT per
// (ride, seq) lands; the loser's ride UPDATE then affects zero rows and its
// orphan revision is compensated away.
func (h *ChangeDestinationHandler) nextAmendmentSeq(ctx context.Context, rideID uuid.UUID) (int, error) {
	var n int
	if err := h.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM destination_fare_amendments WHERE ride_id = $1`, rideID).Scan(&n); err != nil {
		return 0, fmt.Errorf("count destination amendments: %w", err)
	}
	return n + 1, nil
}

// compensateAmendment removes an amendment revision that lost its race before
// ever being referenced by rides.fare_snapshot_id. Best-effort: a failed
// cleanup leaves an unreferenced immutable row (auditable, harmless — the
// pointer never moved and settlement reads only the pointed contract).
func (h *ChangeDestinationHandler) compensateAmendment(ctx context.Context, amendID uuid.UUID) {
	_, _ = h.db.Exec(ctx,
		`DELETE FROM destination_fare_amendments WHERE id = $1
		   AND NOT EXISTS (SELECT 1 FROM rides WHERE fare_snapshot_id = $1)`,
		amendID)
}
