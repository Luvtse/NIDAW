package postgres

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/application/services"
	"nidaw-backend/internal/modules/logix/domain/entities"
	"nidaw-backend/internal/shared/database"
)

// CarrierRepository contains the PostgreSQL query assumptions for load
// matching. The referenced carrier schema is not established by the checked-in
// migration chain; do not wire this adapter into production until that contract
// is confirmed (docs/architecture/logix-load-matching-schema-contract.md).
type CarrierRepository struct {
	db *database.Postgres
}

func NewCarrierRepository(db *database.Postgres) *CarrierRepository {
	return &CarrierRepository{db: db}
}

func (r *CarrierRepository) FindCandidateCarriers(ctx context.Context, load *entities.Load) ([]entities.Carrier, error) {
	if r == nil || r.db == nil {
		return nil, fmt.Errorf("Logix carrier repository database is not configured")
	}
	if load == nil {
		return nil, fmt.Errorf("load is required to find carrier candidates")
	}
	query := `
		SELECT id, company_name, mc_number, fleet_size, equipment_types, service_areas,
		       rating, on_time_rate, insurance_amount, status
		FROM carriers
		WHERE status = 'active'
		AND $1 = ANY(service_areas)
		AND $2 = ANY(service_areas)
		AND $3 = ANY(equipment_types)
		AND insurance_amount >= $4
		ORDER BY rating DESC
		LIMIT 50
	`
	rows, err := r.db.Query(ctx, query, load.Origin.Country, load.Destination.Country, load.EquipmentType, 1000000)
	if err != nil {
		return nil, fmt.Errorf("query candidate carriers: %w", err)
	}
	defer rows.Close()

	carriers := make([]entities.Carrier, 0)
	for rows.Next() {
		var carrier entities.Carrier
		if err := rows.Scan(
			&carrier.ID, &carrier.CompanyName, &carrier.MCNumber, &carrier.FleetSize,
			&carrier.EquipmentTypes, &carrier.ServiceAreas, &carrier.Rating,
			&carrier.OnTimeRate, &carrier.InsuranceAmount, &carrier.Status,
		); err != nil {
			return nil, fmt.Errorf("scan candidate carrier: %w", err)
		}
		carriers = append(carriers, carrier)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate candidate carriers: %w", err)
	}
	return carriers, nil
}

func (r *CarrierRepository) GetCarrierByID(ctx context.Context, carrierID uuid.UUID) (*entities.Carrier, error) {
	if r == nil || r.db == nil {
		return nil, fmt.Errorf("Logix carrier repository database is not configured")
	}
	if carrierID == uuid.Nil {
		return nil, fmt.Errorf("carrier identifier is required")
	}
	var carrier entities.Carrier
	err := r.db.QueryRow(ctx, `
		SELECT id, company_name, mc_number, fleet_size, equipment_types, service_areas,
		       rating, on_time_rate, insurance_amount, status
		FROM carriers WHERE id = $1
	`, carrierID).Scan(
		&carrier.ID, &carrier.CompanyName, &carrier.MCNumber, &carrier.FleetSize,
		&carrier.EquipmentTypes, &carrier.ServiceAreas, &carrier.Rating,
		&carrier.OnTimeRate, &carrier.InsuranceAmount, &carrier.Status,
	)
	if err != nil {
		return nil, fmt.Errorf("load carrier %s: %w", carrierID, err)
	}
	return &carrier, nil
}

var _ services.CarrierRepository = (*CarrierRepository)(nil)
