package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/application/services"
	"nidaw-backend/internal/modules/logix/domain/entities"
	"nidaw-backend/internal/shared/database"
)

// CustomsRepository persists Logix customs workflow state. Multi-row state
// transitions are committed atomically so shipment and declaration status do
// not drift apart when one statement fails.
type CustomsRepository struct {
	db *database.Postgres
}

func NewCustomsRepository(db *database.Postgres) *CustomsRepository {
	return &CustomsRepository{db: db}
}

func (r *CustomsRepository) SavePreparedDeclaration(ctx context.Context, declaration *services.CustomsDeclaration, calculatedDuties float64) error {
	if r == nil || r.db == nil {
		return errors.New("customs database is not configured")
	}
	if declaration == nil {
		return errors.New("customs declaration is required")
	}
	declarationJSON, err := json.Marshal(declaration)
	if err != nil {
		return fmt.Errorf("marshal customs declaration: %w", err)
	}
	_, err = r.db.Exec(ctx, `
		INSERT INTO customs_declarations (id, shipment_id, declaration_data, calculated_duties, status)
		VALUES ($1, $2, $3, $4, 'prepared')
	`, declaration.ID, declaration.ShipmentID, declarationJSON, calculatedDuties)
	if err != nil {
		return fmt.Errorf("insert customs declaration: %w", err)
	}
	return nil
}

func (r *CustomsRepository) MarkDeclarationSubmitted(ctx context.Context, declarationID, shipmentID uuid.UUID, externalID string, submittedAt time.Time) error {
	if r == nil || r.db == nil {
		return errors.New("customs database is not configured")
	}
	return r.db.WithTx(ctx, func(tx *database.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE customs_declarations
			SET external_declaration_id = $1, status = 'submitted', submitted_at = $2
			WHERE id = $3 AND shipment_id = $4 AND status = 'prepared'
		`, externalID, submittedAt, declarationID, shipmentID)
		if err != nil {
			return fmt.Errorf("update customs declaration submission: %w", err)
		}
		if tag.RowsAffected() != 1 {
			return errors.New("customs declaration not found or not in a submittable state")
		}
		tag, err = tx.Exec(ctx, `
			UPDATE shipments
			SET customs_status = 'submitted', status = 'at_customs'
			WHERE id = $1
		`, shipmentID)
		if err != nil {
			return fmt.Errorf("update shipment customs status: %w", err)
		}
		if tag.RowsAffected() != 1 {
			return errors.New("shipment not found while recording customs submission")
		}
		// The domain event is committed with the state transition. A separate
		// dispatcher publishes it after commit and retries failures at least once.
		if err := insertOutboxEvent(ctx, tx, "logix.customs.submitted", "logix.customs", map[string]interface{}{
			"shipment_id": shipmentID, "declaration_id": declarationID, "external_id": externalID,
		}); err != nil {
			return fmt.Errorf("insert customs submission outbox event: %w", err)
		}
		return nil
	})
}

func (r *CustomsRepository) GetExternalDeclaration(ctx context.Context, declarationID uuid.UUID) (string, uuid.UUID, error) {
	if r == nil || r.db == nil {
		return "", uuid.Nil, errors.New("customs database is not configured")
	}
	var externalID string
	var shipmentID uuid.UUID
	if err := r.db.QueryRow(ctx, `
		SELECT external_declaration_id, shipment_id
		FROM customs_declarations
		WHERE id = $1
	`, declarationID).Scan(&externalID, &shipmentID); err != nil {
		return "", uuid.Nil, fmt.Errorf("query external customs declaration: %w", err)
	}
	if externalID == "" {
		return "", uuid.Nil, errors.New("customs declaration has not been submitted")
	}
	return externalID, shipmentID, nil
}

func (r *CustomsRepository) UpdateDeclarationStatus(ctx context.Context, declarationID, shipmentID uuid.UUID, status entities.CustomsStatus, dutiesOwed, taxesOwed float64, clearanceDate *time.Time) error {
	if r == nil || r.db == nil {
		return errors.New("customs database is not configured")
	}
	switch status {
	case entities.CustomsPending, entities.CustomsUnderReview, entities.CustomsCleared, entities.CustomsHeld, entities.CustomsRejected:
	default:
		return fmt.Errorf("unsupported customs status %q", status)
	}
	if math.IsNaN(dutiesOwed) || math.IsInf(dutiesOwed, 0) || dutiesOwed < 0 ||
		math.IsNaN(taxesOwed) || math.IsInf(taxesOwed, 0) || taxesOwed < 0 {
		return errors.New("customs duties and taxes must be finite non-negative amounts")
	}
	return r.db.WithTx(ctx, func(tx *database.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE customs_declarations
			SET status = $1, duties_owed = $2, taxes_owed = $3, clearance_date = $4
			WHERE id = $5 AND shipment_id = $6
			  AND status IN ('submitted', 'pending', 'under_review', 'held')
		`, status, dutiesOwed, taxesOwed, clearanceDate, declarationID, shipmentID)
		if err != nil {
			return fmt.Errorf("update customs declaration status: %w", err)
		}
		if tag.RowsAffected() != 1 {
			return errors.New("customs declaration not found or not awaiting status update")
		}
		if status == entities.CustomsCleared {
			tag, err = tx.Exec(ctx, `
				UPDATE shipments
				SET customs_status = 'cleared', customs_clearance_date = $1, status = 'customs_cleared'
				WHERE id = $2
			`, clearanceDate, shipmentID)
			if err != nil {
				return fmt.Errorf("update cleared shipment status: %w", err)
			}
			if tag.RowsAffected() != 1 {
				return errors.New("shipment not found while recording customs clearance")
			}
			if err := insertOutboxEvent(ctx, tx, "logix.customs.cleared", "logix.customs", map[string]interface{}{
				"shipment_id": shipmentID, "declaration_id": declarationID,
				"duties_owed": dutiesOwed, "taxes_owed": taxesOwed,
			}); err != nil {
				return fmt.Errorf("insert customs clearance outbox event: %w", err)
			}
		}
		return nil
	})
}

var _ services.CustomsRepository = (*CustomsRepository)(nil)

func insertOutboxEvent(ctx context.Context, tx *database.Tx, eventType, topic string, payload map[string]interface{}) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal event payload: %w", err)
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO logix_event_outbox (id, schema_version, event_type, topic, payload, event_timestamp)
		VALUES ($1, 1, $2, $3, $4::jsonb, $5)
	`, uuid.New(), eventType, topic, encoded, time.Now().Unix())
	if err != nil {
		return err
	}
	return nil
}
