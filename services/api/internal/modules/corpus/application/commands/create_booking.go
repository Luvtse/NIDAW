package commands

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/application/ports"
	"nidaw-backend/internal/modules/corpus/domain/bookingdata"
	"nidaw-backend/internal/modules/corpus/domain/entities"
	corpuspolicy "nidaw-backend/internal/modules/corpus/domain/policy"
)

type CreateCorporateBookingCommand struct {
	UserID        uuid.UUID
	CorporateID   uuid.UUID
	ServiceType   entities.ServiceType
	BookingData   map[string]interface{}
	PaymentMethod string // "corporate_account", "personal_reimbursement", "split"
}

type CorporateBookingResult struct {
	BookingID        uuid.UUID
	Status           string
	PolicyCompliant  bool
	Violations       []string
	RequiresApproval bool
	ApproverID       *uuid.UUID
	EstimatedAmount  float64
}

// PolicyEngine is application-level orchestration over the booking repository
// and the pure domain policy evaluator. It owns no SQL or infrastructure.
type PolicyEngine struct{ repository ports.BookingRepository }

func NewPolicyEngine(repository ports.BookingRepository) *PolicyEngine {
	return &PolicyEngine{repository: repository}
}

func (p *PolicyEngine) EvaluateBooking(ctx context.Context, corpID uuid.UUID, serviceType entities.ServiceType, bookingData map[string]interface{}) (*entities.TravelPolicy, []string, error) {
	if p == nil || p.repository == nil {
		return nil, nil, errors.New("corpus policy engine: booking repository is required")
	}
	policy, err := p.repository.FindActivePolicy(ctx, corpID)
	if err != nil {
		return nil, nil, err
	}
	violations, err := corpuspolicy.Evaluate(policy, serviceType, bookingData)
	if err != nil {
		return nil, nil, err
	}
	return policy, violations, nil
}

type CreateCorporateBookingHandler struct {
	repository   ports.BookingRepository
	policyEngine *PolicyEngine
}

func NewCreateCorporateBookingHandler(repository ports.BookingRepository) *CreateCorporateBookingHandler {
	return &CreateCorporateBookingHandler{repository: repository, policyEngine: NewPolicyEngine(repository)}
}

func (h *CreateCorporateBookingHandler) Execute(ctx context.Context, cmd *CreateCorporateBookingCommand) (*CorporateBookingResult, error) {
	if cmd == nil {
		return nil, errors.New("booking command is required")
	}
	if h == nil || h.repository == nil {
		return nil, errors.New("corpus booking repository is required")
	}
	if cmd.UserID == uuid.Nil || cmd.CorporateID == uuid.Nil {
		return nil, errors.New("authenticated user and corporate identifiers are required")
	}
	if cmd.BookingData == nil {
		return nil, errors.New("booking data is required")
	}
	// Decode service-specific version-1 contracts before policy evaluation or
	// persistence. The original map is retained for product-specific fields.
	if _, err := bookingdata.Parse(cmd.ServiceType, cmd.BookingData); err != nil {
		return nil, fmt.Errorf("invalid %s booking contract: %w", cmd.ServiceType, err)
	}
	switch cmd.PaymentMethod {
	case "", "corporate_account", "personal_reimbursement", "split":
	default:
		return nil, errors.New("unsupported corporate booking payment method")
	}
	estimatedAmount, err := corpuspolicy.EstimatedAmount(cmd.BookingData)
	if err != nil {
		return nil, err
	}

	employee, err := h.repository.FindActiveEmployee(ctx, cmd.UserID, cmd.CorporateID)
	if errors.Is(err, ports.ErrEmployeeNotActive) {
		return nil, fmt.Errorf("employee not found or inactive: %w", err)
	}
	if err != nil {
		return nil, fmt.Errorf("load corporate employee: %w", err)
	}
	policy, violations, err := h.policyEngine.EvaluateBooking(ctx, cmd.CorporateID, cmd.ServiceType, cmd.BookingData)
	if err != nil {
		return nil, err
	}

	requiresApproval := len(violations) > 0
	var approverID *uuid.UUID
	for _, rule := range policy.ApprovalRules {
		if rule.ConditionType == "amount" && estimatedAmount > rule.AutoApproveBelow {
			requiresApproval = true
			approverID, err = h.repository.FindApprover(ctx, cmd.CorporateID, rule.ApproverLevel)
			if err != nil {
				return nil, fmt.Errorf("required corporate booking approver could not be resolved: %w", err)
			}
			break
		}
	}
	if estimatedAmount > employee.SpendingLimit {
		requiresApproval = true
	}
	if requiresApproval && approverID == nil {
		return nil, errors.New("booking requires approval but no eligible approver is configured")
	}

	status := "confirmed"
	if requiresApproval {
		status = "pending_approval"
	}
	bookingID := uuid.New()
	now := time.Now().UTC().Unix()
	compliant := len(violations) == 0
	booking := ports.BookingRecord{
		ID: bookingID, EmployeeID: employee.ID, CorporateID: cmd.CorporateID,
		ServiceType: cmd.ServiceType, BookingData: cmd.BookingData, PaymentMethod: cmd.PaymentMethod,
		Status: status, PolicyCompliant: compliant, Violations: violations, EstimatedAmount: estimatedAmount,
		RequiresApproval: requiresApproval, ApproverID: approverID,
	}
	events := []ports.BookingEvent{{SchemaVersion: 1, Type: "corpus.booking.created", Topic: "corpus.bookings", Timestamp: now, Payload: map[string]interface{}{
		"booking_id": bookingID, "employee_id": employee.ID, "corporate_id": cmd.CorporateID,
		"service_type": cmd.ServiceType, "status": status, "policy_compliant": compliant, "estimated_amount": estimatedAmount,
	}}}
	if !requiresApproval {
		topic, topicErr := downstreamTopic(cmd.ServiceType)
		if topicErr != nil {
			return nil, topicErr
		}
		events = append(events, ports.BookingEvent{SchemaVersion: 1, Type: "corpus.booking.approved", Topic: topic, Timestamp: now, Payload: map[string]interface{}{
			"corporate_booking_id": bookingID, "booking_data": cmd.BookingData,
		}})
	}
	if err := h.repository.CreateBookingWithEvents(ctx, booking, events); err != nil {
		return nil, err
	}

	return &CorporateBookingResult{BookingID: bookingID, Status: status, PolicyCompliant: compliant,
		Violations: violations, RequiresApproval: requiresApproval, ApproverID: approverID, EstimatedAmount: estimatedAmount}, nil
}

func downstreamTopic(serviceType entities.ServiceType) (string, error) {
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
