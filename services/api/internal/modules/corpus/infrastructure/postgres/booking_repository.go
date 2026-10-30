package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"nidaw-backend/internal/modules/corpus/application/ports"
	"nidaw-backend/internal/modules/corpus/domain/entities"
	"nidaw-backend/internal/shared/database"
)

// BookingRepository is the PostgreSQL adapter for Corpus booking persistence.
// Booking rows and outbound event records are committed atomically.
type BookingRepository struct{ db *database.Postgres }

func NewBookingRepository(db *database.Postgres) *BookingRepository {
	return &BookingRepository{db: db}
}

func (r *BookingRepository) FindActiveEmployee(ctx context.Context, userID, corporateID uuid.UUID) (*entities.Employee, error) {
	if r == nil || r.db == nil {
		return nil, errors.New("corpus booking repository: database is required")
	}
	var employee entities.Employee
	err := r.db.QueryRow(ctx, `SELECT e.id, e.corporate_id, e.user_id, e.employee_id, e.department, e.role, e.spending_limit, e.approval_level
		FROM corporate_employees e JOIN corporate_accounts a ON a.id = e.corporate_id
		WHERE e.user_id = $1 AND e.corporate_id = $2 AND e.status = 'active' AND a.status = 'active'`, userID, corporateID).Scan(
		&employee.ID, &employee.CorporateID, &employee.UserID, &employee.EmployeeID,
		&employee.Department, &employee.Role, &employee.SpendingLimit, &employee.ApprovalLevel)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ports.ErrEmployeeNotActive
	}
	if err != nil {
		return nil, fmt.Errorf("load active corporate employee: %w", err)
	}
	return &employee, nil
}

func (r *BookingRepository) FindActivePolicy(ctx context.Context, corporateID uuid.UUID) (*entities.TravelPolicy, error) {
	if r == nil || r.db == nil {
		return nil, errors.New("corpus booking repository: database is required")
	}
	var policy entities.TravelPolicy
	err := r.db.QueryRow(ctx, `SELECT id, corporate_id, name, version, ride_policy, hotel_policy, food_policy, freight_policy, approval_rules, is_active
		FROM travel_policies WHERE corporate_id = $1 AND is_active = true ORDER BY effective_from DESC LIMIT 1`, corporateID).Scan(
		&policy.ID, &policy.CorporateID, &policy.Name, &policy.Version, &policy.RidePolicy, &policy.HotelPolicy,
		&policy.FoodPolicy, &policy.FreightPolicy, &policy.ApprovalRules, &policy.IsActive)
	if err != nil {
		return nil, fmt.Errorf("load active travel policy: %w", err)
	}
	return &policy, nil
}

func (r *BookingRepository) FindApprover(ctx context.Context, corporateID uuid.UUID, minimumLevel int) (*uuid.UUID, error) {
	if r == nil || r.db == nil {
		return nil, errors.New("corpus booking repository: database is required")
	}
	var id uuid.UUID
	err := r.db.QueryRow(ctx, `SELECT id FROM corporate_employees
		WHERE corporate_id = $1 AND manager_id IS NOT NULL AND status = 'active' AND approval_level >= $2
		ORDER BY approval_level ASC, id ASC LIMIT 1`, corporateID, minimumLevel).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ports.ErrApproverNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("resolve corporate booking approver: %w", err)
	}
	return &id, nil
}

func (r *BookingRepository) CreateBookingWithEvents(ctx context.Context, booking ports.BookingRecord, events []ports.BookingEvent) error {
	if r == nil || r.db == nil {
		return errors.New("corpus booking repository: database is required")
	}
	bookingData, err := json.Marshal(booking.BookingData)
	if err != nil {
		return fmt.Errorf("encode booking data: %w", err)
	}
	return r.db.WithTx(ctx, func(tx *database.Tx) error {
		_, err := tx.Exec(ctx, `INSERT INTO corporate_bookings
			(id, employee_id, corporate_id, service_type, booking_data, payment_method, status, policy_compliant, violations, estimated_amount, requires_approval, approver_id)
			VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9, $10, $11, $12)`,
			booking.ID, booking.EmployeeID, booking.CorporateID, booking.ServiceType, string(bookingData), booking.PaymentMethod,
			booking.Status, booking.PolicyCompliant, booking.Violations, booking.EstimatedAmount, booking.RequiresApproval, booking.ApproverID)
		if err != nil {
			return fmt.Errorf("insert corporate booking: %w", err)
		}
		for _, ev := range events {
			payload, marshalErr := json.Marshal(ev.Payload)
			if marshalErr != nil {
				return fmt.Errorf("encode %s event payload: %w", ev.Type, marshalErr)
			}
			_, err = tx.Exec(ctx, `INSERT INTO corpus_event_outbox (id, event_type, topic, payload, event_timestamp, schema_version, status, available_at)
				VALUES ($1, $2, $3, $4::jsonb, $5, $6, 'pending', now())`, uuid.New(), ev.Type, ev.Topic, string(payload), ev.Timestamp, normalizedSchemaVersion(ev.SchemaVersion))
			if err != nil {
				return fmt.Errorf("persist %s outbox event: %w", ev.Type, err)
			}
		}
		return nil
	})
}

var _ ports.BookingRepository = (*BookingRepository)(nil)

func normalizedSchemaVersion(version int) int {
	if version < 1 {
		return 1
	}
	return version
}

// DecideBooking checks the assigned approver, changes the state, and appends
// the product handoff event in the same transaction. A repeated decision is
// rejected rather than producing duplicate approval events.
func (r *BookingRepository) DecideBooking(ctx context.Context, bookingID, approverUserID uuid.UUID, approve bool, notes string) error {
	if r == nil || r.db == nil {
		return errors.New("corpus booking repository: database is required")
	}
	return r.db.WithTx(ctx, func(tx *database.Tx) error {
		var status string
		var serviceType entities.ServiceType
		var corporateID, approverEmployeeID uuid.UUID
		var bookingData map[string]interface{}
		err := tx.QueryRow(ctx, `SELECT b.status, b.service_type, b.corporate_id, b.approver_id, b.booking_data
			FROM corporate_bookings b
			JOIN corporate_employees e ON e.id = b.approver_id
			JOIN corporate_accounts a ON a.id = b.corporate_id
			WHERE b.id = $1 AND e.user_id = $2 AND e.status = 'active' AND a.status = 'active'
			FOR UPDATE OF b`, bookingID, approverUserID).Scan(&status, &serviceType, &corporateID, &approverEmployeeID, &bookingData)
		if errors.Is(err, pgx.ErrNoRows) {
			return ports.ErrApprovalNotAssigned
		}
		if err != nil {
			return fmt.Errorf("load assigned Corpus booking approval: %w", err)
		}
		if status != "pending_approval" {
			return ports.ErrBookingNotPending
		}

		now := time.Now().UTC().Unix()
		decision := "rejected"
		eventType := "corpus.booking.rejected"
		topic := "corpus.bookings"
		if approve {
			decision = "confirmed"
			eventType = "corpus.booking.approved"
			var topicErr error
			topic, topicErr = corpusDownstreamTopic(serviceType)
			if topicErr != nil {
				return topicErr
			}
		}
		_, err = tx.Exec(ctx, `UPDATE corporate_bookings SET status = $2, approval_decided_at = to_timestamp($3), approval_notes = $4, updated_at = now()
			WHERE id = $1 AND status = 'pending_approval'`, bookingID, decision, now, notes)
		if err != nil {
			return fmt.Errorf("record Corpus booking decision: %w", err)
		}
		payload := map[string]interface{}{
			"corporate_booking_id":    bookingID,
			"corporate_id":            corporateID,
			"service_type":            serviceType,
			"approved_by_employee_id": approverEmployeeID,
			"approval_notes":          notes,
		}
		if approve {
			payload["booking_data"] = bookingData
		}
		encoded, err := json.Marshal(payload)
		if err != nil {
			return fmt.Errorf("encode Corpus booking decision event: %w", err)
		}
		_, err = tx.Exec(ctx, `INSERT INTO corpus_event_outbox (id, event_type, topic, payload, event_timestamp, schema_version, status, available_at)
			VALUES ($1, $2, $3, $4::jsonb, $5, 1, 'pending', now())`, uuid.New(), eventType, topic, string(encoded), now)
		if err != nil {
			return fmt.Errorf("persist Corpus booking decision event: %w", err)
		}
		return nil
	})
}

func corpusDownstreamTopic(serviceType entities.ServiceType) (string, error) {
	switch serviceType {
	case entities.ServiceRides:
		return "nidus.rides", nil
	case entities.ServiceHotels:
		return "haven.bookings", nil
	case entities.ServiceFood:
		return "vorax.orders", nil
	case entities.ServiceFreight:
		return "logix.shipments", nil
	default:
		return "", fmt.Errorf("unsupported corporate booking service type %q", serviceType)
	}
}
