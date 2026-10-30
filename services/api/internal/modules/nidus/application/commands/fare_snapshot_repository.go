// Package commands — NIDAW FARE INTEGRITY (Phase 1): persistence contract
// for immutable booking fare snapshots.
//
// The repository is the ONLY way a FareSnapshot reaches or leaves the
// database. Two rules shape its surface:
//
//  1. Create-or-get idempotency. CreateSnapshot inserts keyed by
//     IdempotencyKey; a duplicate key never errors and never writes a second
//     row — it returns the ORIGINAL stored snapshot unchanged. A retried ride
//     request therefore cannot mint two different contracts, and the caller
//     can detect that a pre-existing row won by comparing IDs.
//
//  2. No mutation API on purpose. There is deliberately no UpdateSnapshot:
//     frozen contracts are corrected only through NEW approved additions
//     (stops) or a NEW revision after explicit rider approval. The database
//     backs this up with a BEFORE UPDATE immutability trigger
//     (migration 027_nidus_fare_snapshot.sql), so even a rogue code path
//     editing SQL directly fails loudly.
package commands

import (
	"context"
	"errors"
	"fmt"
	"time"

	"nidaw-backend/internal/modules/nidus/domain/entities"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ErrFareSnapshotIncomplete means a persisted row failed entity validation on
// read-back (e.g. currency drift or components not reconciling with the
// quoted total). Callers must treat this as a data-integrity incident and
// refuse settlement rather than paper over it.
var ErrFareSnapshotIncomplete = errors.New("stored fare snapshot failed integrity validation")

// FareSnapshotRepository is the persistence port for the booking contract.
// It is satisfied by *PostgresFareSnapshotRepository; tests may inject fakes.
type FareSnapshotRepository interface {
	// CreateSnapshot stores an immutable snapshot. Inserting the same
	// IdempotencyKey twice returns the originally stored row unchanged
	// (create-or-get semantics); the returned bool reports whether THIS call
	// created the row (false => an existing snapshot was returned).
	CreateSnapshot(ctx context.Context, snapshot *entities.FareSnapshot) (*entities.FareSnapshot, bool, error)

	// GetSnapshotByRideID loads the ride's frozen contract. Returns
	// entities.ErrFareSnapshotNil-wrapping pgx.ErrNoRows semantics via
	// errors.Is(err, ErrFareSnapshotNotFound) when the ride predates Phase 1
	// or was never priced server-side.
	GetSnapshotByRideID(ctx context.Context, rideID uuid.UUID) (*entities.FareSnapshot, error)
}

// ErrFareSnapshotNotFound signals a ride without a stored contract. The
// completion path maps this to a refusal to settle (never a reprice).
var ErrFareSnapshotNotFound = errors.New("fare snapshot not found for ride")

// PostgresFareSnapshotRepository implements FareSnapshotRepository against
// the ride_fare_snapshots table (migration 027). Money columns are BIGINT
// santim exactly as in the entity — no float round-trips at the boundary.
type PostgresFareSnapshotRepository struct {
	db DBTX
}

// DBTX is the narrow executor interface shared with the rest of the module's
// repositories (satisfied by *database.Postgres and *database.Tx), keeping
// this file testable without a live pool. Exec returns pgconn.CommandTag in
// both concrete types, so the signature matches them directly.
type DBTX interface {
	QueryRow(ctx context.Context, sql string, args ...interface{}) pgx.Row
	Exec(ctx context.Context, sql string, args ...interface{}) (pgconn.CommandTag, error)
}

// NewPostgresFareSnapshotRepository constructs the repository.
func NewPostgresFareSnapshotRepository(db DBTX) *PostgresFareSnapshotRepository {
	return &PostgresFareSnapshotRepository{db: db}
}

const fareSnapshotColumns = `id, ride_id, idempotency_key,
	pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
	COALESCE(pickup_address, ''), COALESCE(dropoff_address, ''),
	contract_distance_km, contract_duration_min,
	base_fare_santim, distance_fare_santim, time_fare_santim,
	surge_amount_santim, minimum_fare_santim, gross_fare_santim,
	ride_type, distance_rate_per_km, time_rate_per_minute,
	surge_multiplier, COALESCE(surge_reason, ''), minutes_per_km,
	pricing_config_version, duration_rule_version,
	currency, quoted_total_santim, frozen_at`

func scanFareSnapshot(row pgx.Row) (*entities.FareSnapshot, error) {
	var s entities.FareSnapshot
	err := row.Scan(
		&s.ID, &s.RideID, &s.IdempotencyKey,
		&s.PickupLat, &s.PickupLng, &s.DropoffLat, &s.DropoffLng,
		&s.PickupAddress, &s.DropoffAddress,
		&s.ContractDistanceKm, &s.ContractDurationMin,
		&s.Components.BaseFareSantim, &s.Components.DistanceFareSantim, &s.Components.TimeFareSantim,
		&s.Components.SurgeAmountSantim, &s.Components.MinimumFareSantim, &s.Components.GrossFareSantim,
		&s.Components.RideType, &s.Components.DistanceRatePerKm, &s.Components.TimeRatePerMinute,
		&s.Components.SurgeMultiplier, &s.Components.SurgeReason, &s.MinutesPerKm,
		&s.PricingConfigVersion, &s.DurationRuleVersion,
		&s.Currency, &s.QuotedTotalSantim, &s.FrozenAt,
	)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// CreateSnapshot persists the contract with create-or-get idempotency.
// The snapshot must already satisfy its own invariants (ETB, reconciliation)
// — Validate() runs BEFORE any INSERT so a corrupt object never touches the
// database. ON CONFLICT (idempotency_key) DO NOTHING followed by a read-back
// guarantees a retry returns the original row instead of a second contract.
func (r *PostgresFareSnapshotRepository) CreateSnapshot(ctx context.Context, snapshot *entities.FareSnapshot) (*entities.FareSnapshot, bool, error) {
	if snapshot == nil {
		return nil, false, entities.ErrFareSnapshotNil
	}
	if err := snapshot.Validate(); err != nil {
		return nil, false, fmt.Errorf("refusing to persist invalid fare snapshot: %w", err)
	}
	if snapshot.IdempotencyKey == "" {
		return nil, false, errors.New("fare snapshot requires an idempotency key")
	}

	frozenAt := snapshot.FrozenAt
	if frozenAt.IsZero() {
		frozenAt = time.Now().UTC()
	}

	tag, err := r.db.Exec(ctx, `
		INSERT INTO ride_fare_snapshots (
			id, ride_id, idempotency_key,
			pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
			pickup_address, dropoff_address,
			contract_distance_km, contract_duration_min,
			base_fare_santim, distance_fare_santim, time_fare_santim,
			surge_amount_santim, minimum_fare_santim, gross_fare_santim,
			ride_type, distance_rate_per_km, time_rate_per_minute,
			surge_multiplier, surge_reason, minutes_per_km,
			pricing_config_version, duration_rule_version,
			currency, quoted_total_santim, frozen_at
		) VALUES (
			$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28
		)
		ON CONFLICT (idempotency_key) DO NOTHING`,
		snapshot.ID, snapshot.RideID, snapshot.IdempotencyKey,
		snapshot.PickupLat, snapshot.PickupLng, snapshot.DropoffLat, snapshot.DropoffLng,
		nullString(snapshot.PickupAddress), nullString(snapshot.DropoffAddress),
		snapshot.ContractDistanceKm, snapshot.ContractDurationMin,
		snapshot.Components.BaseFareSantim, snapshot.Components.DistanceFareSantim, snapshot.Components.TimeFareSantim,
		snapshot.Components.SurgeAmountSantim, snapshot.Components.MinimumFareSantim, snapshot.Components.GrossFareSantim,
		snapshot.Components.RideType, snapshot.Components.DistanceRatePerKm, snapshot.Components.TimeRatePerMinute,
		snapshot.Components.SurgeMultiplier, nullString(snapshot.Components.SurgeReason), snapshot.MinutesPerKm,
		snapshot.PricingConfigVersion, snapshot.DurationRuleVersion,
		snapshot.Currency, snapshot.QuotedTotalSantim, frozenAt,
	)
	if err != nil {
		return nil, false, err
	}

	created := rowCount(tag) > 0
	if created {
		return snapshot, true, nil
	}

	// Conflict: the contract already exists under this idempotency key.
	// Return the STORED row — authoritative, byte-identical to the first
	// successful create — never the caller's freshly computed candidate.
	existing, err := r.getSnapshotByKey(ctx, snapshot.IdempotencyKey)
	if err != nil {
		return nil, false, err
	}
	return existing, false, nil
}

// GetSnapshotByRideID loads the frozen contract for a ride.
func (r *PostgresFareSnapshotRepository) GetSnapshotByRideID(ctx context.Context, rideID uuid.UUID) (*entities.FareSnapshot, error) {
	s, err := scanFareSnapshot(r.db.QueryRow(ctx,
		`SELECT `+fareSnapshotColumns+` FROM ride_fare_snapshots WHERE ride_id = $1`, rideID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("%w: %s", ErrFareSnapshotNotFound, rideID)
	}
	if err != nil {
		return nil, err
	}
	if err := s.Validate(); err != nil {
		return nil, fmt.Errorf("%w (ride %s, snapshot %s): %v", ErrFareSnapshotIncomplete, s.RideID, s.ID, err)
	}
	return s, nil
}

func (r *PostgresFareSnapshotRepository) getSnapshotByKey(ctx context.Context, key string) (*entities.FareSnapshot, error) {
	s, err := scanFareSnapshot(r.db.QueryRow(ctx,
		`SELECT `+fareSnapshotColumns+` FROM ride_fare_snapshots WHERE idempotency_key = $1`, key))
	if errors.Is(err, pgx.ErrNoRows) {
		// Race window: the conflicting insert rolled back between our Exec and
		// the read-back. Surface as not-found; the request path retries cleanly.
		return nil, fmt.Errorf("%w: key %q", ErrFareSnapshotNotFound, key)
	}
	if err != nil {
		return nil, err
	}
	if err := s.Validate(); err != nil {
		return nil, fmt.Errorf("%w (snapshot %s): %v", ErrFareSnapshotIncomplete, s.ID, err)
	}
	return s, nil
}

// LinkRideSnapshot stamps rides.fare_snapshot_id once the contract row is
// committed, so every consumer can locate THE contract from the ride row.
// Best-effort at the call site but strict here: zero rows affected means the
// ride vanished (compensation delete) and is reported as an error.
func LinkRideSnapshot(ctx context.Context, db DBTX, rideID, snapshotID uuid.UUID) error {
	tag, err := db.Exec(ctx,
		`UPDATE rides SET fare_snapshot_id = $2, updated_at = NOW() WHERE id = $1 AND fare_snapshot_id IS NULL`,
		rideID, snapshotID)
	if err != nil {
		return err
	}
	if rowCount(tag) == 0 {
		return fmt.Errorf("link fare snapshot: ride %s not found or already linked", rideID)
	}
	return nil
}

// nullString maps "" to a SQL NULL so nullable TEXT columns stay honest.
func nullString(v string) interface{} {
	if v == "" {
		return nil
	}
	return v
}

// rowCount normalizes the pgconn.CommandTag returned through the narrow DBTX
// interface. CommandTag is a concrete struct with RowsAffected(); we accept it
// directly (no reflection needed since DBTX.Exec now returns it typed).
func rowCount(tag pgconn.CommandTag) int64 {
	return tag.RowsAffected()
}
