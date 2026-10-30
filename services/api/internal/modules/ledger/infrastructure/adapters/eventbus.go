// Package adapters bridges the ledger command layer to the rest of the
// NIDAW platform: Kafka events (inbound ride.completed, outbound domain
// events) and shared infrastructure. Phase E/G will add provider adapters
// (Telebirr / Chapa / M-Pesa) and the fraud evaluator beside these.
package adapters

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/google/uuid"

	"nidaw-backend/internal/modules/ledger/application/commands"
	"nidaw-backend/internal/modules/ledger/application/services"
	nidusevents "nidaw-backend/internal/modules/nidus/domain/events"
	"nidaw-backend/internal/shared/eventbus"
)

// ============================================================================
// OUTBOUND: commands.EventPublisher -> eventbus.EventBus
// ============================================================================

// EventBusPublisher writes event records into PostgreSQL using the caller
// transaction. A separate dispatcher publishes committed records to Kafka.
type EventBusPublisher struct {
	bus   eventbus.EventBus
	topic string // default "nidaw.events" (matches KafkaBus writer default)
}

// NewEventBusPublisher wires the ledger to the platform event bus.
func NewEventBusPublisher(bus eventbus.EventBus) *EventBusPublisher {
	return &EventBusPublisher{bus: bus, topic: "nidaw.events"}
}

// SetTopic overrides the publish topic (tests / multi-tenant deployments).
func (p *EventBusPublisher) SetTopic(topic string) { p.topic = topic }

// Publish persists the event in the caller's transaction. The Kafka publish is
// intentionally deferred to OutboxDispatcher so a broker outage cannot split
// a committed ledger mutation from its event record.
func (p *EventBusPublisher) Publish(ctx context.Context, tx services.DBTx, ev commands.Event) error {
	if tx == nil {
		return fmt.Errorf("ledger outbox: transaction is required")
	}
	topic := ev.Topic
	if topic == "" {
		topic = p.topic
	}
	payload, err := json.Marshal(ev.Payload)
	if err != nil {
		return fmt.Errorf("ledger outbox: encode payload: %w", err)
	}
	_, err = tx.Exec(ctx, `INSERT INTO ledger_event_outbox
   (id, event_type, topic, payload, event_timestamp, status, available_at)
   VALUES ($1, $2, $3, $4::jsonb, $5, 'pending', now())`,
		uuid.New(), ev.Type, topic, string(payload), ev.Timestamp)
	if err != nil {
		return fmt.Errorf("ledger outbox: persist event: %w", err)
	}
	return nil
}

var _ commands.EventPublisher = (*EventBusPublisher)(nil)

// ============================================================================
// INBOUND: ride.completed consumer -> ProcessRidePayment
// ============================================================================

// RideSettlementHandler consumes "ride.completed" events from the nidus rides
// topic and settles fares through the ledger (escrow credit included). It is
// safe for concurrent use; idempotency is enforced inside the ledger
// (ride-id key), so Kafka redelivery cannot double-charge.
type RideSettlementHandler struct {
	deps *commands.Deps
}

// NewRideSettlementHandler constructs the consumer callback.
func NewRideSettlementHandler(deps *commands.Deps) *RideSettlementHandler {
	return &RideSettlementHandler{deps: deps}
}

// Handle processes one eventbus.Event of type "ride.completed". Unknown types
// are ignored so it can be registered on a wildcard subscription.
func (h *RideSettlementHandler) Handle(ctx context.Context, ev eventbus.Event) error {
	if ev.Type != nidusevents.RideCompletedType {
		return nil
	}
	payload, err := decodePayload(ev.Payload)
	if err != nil {
		return fmt.Errorf("ledger adapter: ride.completed payload: %w", err)
	}
	settleCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	_, err = commands.ProcessRidePayment(settleCtx, h.deps, nil, payload)
	if err == commands.ErrRideAlreadySettled {
		// Duplicate delivery — acknowledge, nothing to do.
		return nil
	}
	return err
}

// decodePayload converts the loosely-typed Kafka payload into the strongly
// typed command DTO. A json round-trip tolerates uuid/string/number variance
// emitted by different producers.
//
// PHASE 3 (settlement integrity): when the payload carries the integer ETB
// santim settlement fields emitted by the nidus completion command, they are
// decoded verbatim into a RideSettlementContract and VALIDATED before use —
// the ledger debits the rider the PAYABLE amount (promo discount included),
// credits the driver the CONTRACT earnings and records the tip separately.
// The legacy float fields (final_fare / platform_fee) are only used as a
// fallback for pre-contract producers; mixed payloads must reconcile or the
// event is rejected loudly rather than silently picking different numbers.
func decodePayload(in map[string]interface{}) (commands.RideCompletedEvent, error) {
	var out commands.RideCompletedEvent
	raw, err := json.Marshal(in)
	if err != nil {
		return out, err
	}
	var wire struct {
		RideID                string  `json:"ride_id"`
		DriverID              string  `json:"driver_id"`
		UserID                string  `json:"user_id"`
		FinalFare             float64 `json:"final_fare"`
		PlatformFee           float64 `json:"platform_fee"`
		Currency              string  `json:"currency"`
		CompletedAtUnix       int64   `json:"completed_at_unix"`
		PaymentMethodType     string  `json:"payment_method_type"`
		SettlementIdempotency string  `json:"settlement_idempotency"`
		FareSnapshotID        string  `json:"fare_snapshot_id"`
		PendingCashCollection bool    `json:"pending_cash_collection"`
		// ---- Authoritative integer-santim settlement contract ----------------
		BookingFareSantim    *int64 `json:"booking_fare_santim"`
		StopFeesSantim       *int64 `json:"stop_fees_santim"`
		WaitingChargesSantim *int64 `json:"waiting_charges_santim"`
		GrossFareSantim      *int64 `json:"gross_fare_santim"`
		DiscountSantim       *int64 `json:"discount_santim"`
		PayableFareSantim    *int64 `json:"payable_fare_santim"`
		CommissionSantim     *int64 `json:"commission_santim"`
		DriverEarningsSantim *int64 `json:"driver_earnings_santim"`
		TipSantim            *int64 `json:"tip_santim"`
	}
	if err := json.Unmarshal(raw, &wire); err != nil {
		return out, err
	}
	if out.RideID, err = uuid.Parse(wire.RideID); err != nil {
		return out, fmt.Errorf("ride_id: %w", err)
	}
	if out.DriverID, err = uuid.Parse(wire.DriverID); err != nil {
		return out, fmt.Errorf("driver_id: %w", err)
	}
	if out.RiderID, err = uuid.Parse(wire.UserID); err != nil {
		return out, fmt.Errorf("user_id: %w", err)
	}
	out.Currency = wire.Currency
	if out.Currency == "" {
		out.Currency = "ETB"
	}
	if out.Currency != "ETB" {
		// Reject, never coerce: an inbound USD/mislabeled settlement must not
		// settle against ETB balances under an ETB label.
		return out, fmt.Errorf("%w: ride.completed currency %q is not ETB",
			commands.ErrSettlementContractRejected, out.Currency)
	}
	out.CompletedAtUnix = wire.CompletedAtUnix
	if out.CompletedAtUnix == 0 {
		out.CompletedAtUnix = time.Now().UTC().Unix()
	}

	// Contract path: every authoritative leg present => consume verbatim.
	if wire.GrossFareSantim != nil && wire.PayableFareSantim != nil &&
		wire.CommissionSantim != nil && wire.DriverEarningsSantim != nil &&
		wire.BookingFareSantim != nil {
		deref := func(p *int64) int64 {
			if p == nil {
				return 0
			}
			return *p
		}
		contract := commands.RideSettlementContract{
			RideID:                wire.RideID,
			RiderID:               out.RiderID.String(),
			DriverID:              out.DriverID.String(),
			SettlementID:          wire.RideID, // deterministic: one settlement per ride
			FareSnapshotID:        wire.FareSnapshotID,
			IdempotencyKey:        wire.SettlementIdempotency,
			PaymentMethod:         wire.PaymentMethodType,
			PendingCashCollection: wire.PendingCashCollection,
			CompletedAtUnix:       out.CompletedAtUnix,
			BookingFareSantim:     deref(wire.BookingFareSantim),
			StopFeesSantim:        deref(wire.StopFeesSantim),
			WaitingChargesSantim:  deref(wire.WaitingChargesSantim),
			GrossFareSantim:       deref(wire.GrossFareSantim),
			DiscountSantim:        deref(wire.DiscountSantim),
			PayableSantim:         deref(wire.PayableFareSantim),
			CommissionSantim:      deref(wire.CommissionSantim),
			DriverEarningsSantim:  deref(wire.DriverEarningsSantim),
			TipSantim:             deref(wire.TipSantim),
			Currency:              out.Currency,
		}
		if verr := contract.Validate(); verr != nil {
			return out, verr
		}
		// Cross-check the display floats against the integers when both are
		// present: a producer whose float disagrees with its santim contract is
		// broken; refuse rather than choosing a winner.
		if wire.FinalFare != 0 && etbToCents(wire.FinalFare) != contract.GrossFareSantim {
			return out, fmt.Errorf("%w: final_fare %.2f does not match gross_fare_santim %d",
				commands.ErrSettlementContractRejected, wire.FinalFare, contract.GrossFareSantim)
		}
		if wire.PlatformFee != 0 && etbToCents(wire.PlatformFee) != contract.CommissionSantim {
			return out, fmt.Errorf("%w: platform_fee %.2f does not match commission_santim %d",
				commands.ErrSettlementContractRejected, wire.PlatformFee, contract.CommissionSantim)
		}
		out.Contract = &contract
		// Legacy fields mirror the contract legs so any consumer still reading
		// them sees the payable (post-discount), not the gross.
		out.FareCents = contract.PayableSantim
		out.FeeCents = contract.CommissionSantim
		return out, nil
	}

	// Legacy producer path (no santim contract on the wire): ETB floats ->
	// cents (round half away from zero), unchanged semantics.
	out.FareCents = etbToCents(wire.FinalFare)
	out.FeeCents = etbToCents(wire.PlatformFee)
	if out.FareCents <= 0 {
		return out, fmt.Errorf("invalid final_fare %s", strconv.FormatFloat(wire.FinalFare, 'f', 2, 64))
	}
	return out, nil
}

// etbToCents rounds an ETB amount to cents, half away from zero.
func etbToCents(etb float64) int64 {
	c := etb * 100
	if c >= 0 {
		return int64(c + 0.5)
	}
	return int64(c - 0.5)
}
