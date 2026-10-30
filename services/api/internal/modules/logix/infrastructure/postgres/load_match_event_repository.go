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

// LoadMatchEventRepository stores the versioned load-matched event in the same
// durable Logix outbox used by customs workflow events. Delivery is at least
// once; consumers must deduplicate using the event_id envelope field.
type LoadMatchEventRepository struct {
	db *database.Postgres
}

func NewLoadMatchEventRepository(db *database.Postgres) *LoadMatchEventRepository {
	return &LoadMatchEventRepository{db: db}
}

func (r *LoadMatchEventRepository) RecordLoadMatched(ctx context.Context, load *entities.Load, carrierID uuid.UUID, score float64) error {
	if r == nil || r.db == nil {
		return errors.New("load-match event database is not configured")
	}
	if load == nil || load.ID == uuid.Nil || carrierID == uuid.Nil {
		return errors.New("load and carrier identifiers are required")
	}
	if math.IsNaN(score) || math.IsInf(score, 0) || score < 0 || score > 100 {
		return errors.New("load-match score must be finite and between 0 and 100")
	}
	if math.IsNaN(load.Rate) || math.IsInf(load.Rate, 0) || load.Rate < 0 {
		return errors.New("load rate must be finite and non-negative")
	}

	payload, err := json.Marshal(map[string]interface{}{
		"load_id": load.ID.String(), "carrier_id": carrierID.String(),
		"score": score, "rate": load.Rate,
	})
	if err != nil {
		return fmt.Errorf("marshal load-matched event: %w", err)
	}
	eventID := uuid.New()
	return r.db.WithTx(ctx, func(tx *database.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO logix_event_outbox (id, schema_version, event_type, topic, payload, event_timestamp)
			VALUES ($1, 1, 'logix.load.matched', 'logix.loads', $2::jsonb, $3)
		`, eventID, payload, time.Now().Unix())
		if err != nil {
			return fmt.Errorf("insert load-matched event into outbox: %w", err)
		}
		return nil
	})
}

var _ services.LoadMatchEventWriter = (*LoadMatchEventRepository)(nil)
