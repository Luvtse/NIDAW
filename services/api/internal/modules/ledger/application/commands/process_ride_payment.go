package commands

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"nidaw-backend/internal/modules/ledger/application/services"
	"nidaw-backend/internal/modules/ledger/domain/entities"
	"nidaw-backend/internal/modules/ledger/domain/valueobjects"
)

// ============================================================================
// PROCESS RIDE PAYMENT (Phase D Step 5 / Phase F Step 1 trigger /
// Phase 3 authoritative settlement contract)
// ============================================================================
//
// Consumes the ride.completed event and settles the fare atomically:
//   1. Debit rider available balance (ride_debit) by the CONTRACT payable —
//      max(0, gross - promo discount) — never by the gross fare. The promo
//      discount is platform-funded: it lowers what the rider pays but does
//      NOT lower driver earnings or the commission basis (§2.6).
//   2. Credit driver into HELD bucket — escrow, not spendable yet
//      (ride_credit_held) — by the CONTRACT driver earnings
//      (gross - commission), and open an escrow_hold with
//      release_after = now + 72h.
// When the event carries the integer-santim settlement contract (see
// ride_settlement_contract.go), every leg comes from that validated
// contract; the legacy float fields are honored only for pre-contract
// producers. Tips are separately identified and NEVER moved here — the
// dedicated tip policy settles them straight to the driver's available
// balance exactly once per ride (nidus TipSettler); this command records
// the tip on the settlement event so receipt/earnings surfaces read the
// same authoritative number.
// All movements commit in one DB transaction; a failure rolls back the
// debit as well, so no fare can be half-charged. Idempotency is keyed on
// the ride id so Kafka redelivery cannot double-charge. Cash rides settle
// against the SAME payable amount when collection is confirmed upstream —
// the money legs here do not vary by payment method.

// ErrRideAlreadySettled signals a duplicate ride.completed delivery.
var ErrRideAlreadySettled = errors.New("ledger: ride already settled")

// RideCompletedEvent mirrors the payload of the "ride.completed" Kafka event.
// Contract is the authoritative santim settlement document; when non-nil (and
// valid) its amounts take precedence over the legacy float-derived FareCents /
// FeeCents fields below.
type RideCompletedEvent struct {
	RideID          uuid.UUID
	RiderID         uuid.UUID
	DriverID        uuid.UUID
	FareCents       int64  // ETB cents charged to the rider
	FeeCents        int64  // platform fee taken out of the fare (driver credited net)
	Currency        string // must be ETB
	CompletedAtUnix int64

	// ---- Phase 3 authoritative settlement contract (integer ETB santim) ----
	Contract *RideSettlementContract // nil => legacy producer, float fields above
}

// SettlementLegs exposes the four money legs of this settlement: rider
// debit (payable), platform commission, driver held credit and tip. Exported
// so infrastructure adapters and reconciliation jobs can prove what
// ProcessRidePayment will settle without executing it. With a contract
// present the numbers come verbatim from the validated santim document;
// otherwise the legacy gross/commission pair is used and the driver credit
// is derived deterministically as gross - commission.
func (ev RideCompletedEvent) SettlementLegs() (debit, commission, driverCredit, tip int64, currency string, err error) {
	currency = ev.Currency
	if currency == "" {
		currency = ContractCurrency
	}
	if ev.Contract != nil {
		if verr := ev.Contract.Validate(); verr != nil {
			return 0, 0, 0, 0, currency, verr
		}
		debit, driverCredit, commission, tip = ev.Contract.ReconcileBalance()
		return debit, commission, driverCredit, tip, ev.Contract.Currency, nil
	}
	if ev.FareCents <= 0 {
		return 0, 0, 0, 0, currency, errors.New("ledger: ride fare must be positive")
	}
	if ev.FeeCents < 0 || ev.FeeCents > ev.FareCents {
		return 0, 0, 0, 0, currency, errors.New("ledger: platform fee exceeds fare")
	}
	return ev.FareCents, ev.FeeCents, ev.FareCents - ev.FeeCents, 0, currency, nil
}

// ProcessRidePayment handles one ride.completed settlement.
func ProcessRidePayment(ctx context.Context, d *Deps, log *zap.Logger, ev RideCompletedEvent) (*entities.EscrowHold, error) {
	if ev.RideID == uuid.Nil || ev.RiderID == uuid.Nil || ev.DriverID == uuid.Nil {
		return nil, errors.New("ledger: ride payment requires ride, rider and driver ids")
	}
	payableCents, commissionCents, driverCreditCents, tipCents, currency, err := ev.SettlementLegs()
	if err != nil {
		return nil, err
	}
	if currency != ContractCurrency {
		// Reject, never coerce: a mislabeled currency must not silently settle.
		return nil, fmt.Errorf("%w: settlement currency %q is not ETB", ErrSettlementContractRejected, currency)
	}
	fare, err := valueobjects.NewMoney(payableCents)
	if err != nil {
		return nil, err
	}
	driverNet, err := valueobjects.NewMoney(driverCreditCents)
	if err != nil {
		return nil, err
	}

	rideStr := ev.RideID.String()
	debitKey := "ride:debit:" + rideStr
	creditKey := "ride:credit:" + rideStr

	// Contract identity fields flow through to the settlement event so every
	// consumer can locate the immutable booking contract and dedupe on the
	// same idempotency key the producer used. Legacy events fall back to the
	// deterministic per-ride debit key.
	idempotencyKey, snapshotID, pendingCash := debitKey, "", false
	if c := ev.Contract; c != nil {
		if c.IdempotencyKey != "" {
			idempotencyKey = c.IdempotencyKey
		}
		snapshotID = c.FareSnapshotID
		pendingCash = c.PendingCashCollection
	}

	var hold *entities.EscrowHold
	err = d.Uow.WithTx(ctx, func(tx services.DBTx) error {
		// Double-submit guard: has this ride already been debited from the rider?
		found, _, err := d.Txs.ExistsIdempotencyKey(ctx, tx, ev.RiderID, debitKey)
		if err != nil {
			return err
		}
		if found {
			return ErrRideAlreadySettled
		}

		// 1. Debit the rider by the CONTRACT PAYABLE (post-discount amount —
		//    the promo discount never reaches the rider's debit; §2.5). Fails
		//    fast if funds are insufficient — the rider must top up before
		//    rides are auto-settled; negative_lock is NOT allowed here, riders
		//    settle from prepaid balance only.
		if _, err := d.Ledger.Debit(ctx, ev.RiderID, fare, valueobjects.TxTypeRideDebit, false, services.CreditOptions{
			IdempotencyKey: debitKey,
			ReferenceID:    &ev.RideID,
			ReferenceType:  "ride",
			Description:    fmt.Sprintf("Ride %s payable fare", rideStr),
		}); err != nil {
			return fmt.Errorf("ledger: rider debit: %w", err)
		}

		// 2. Credit the driver's HELD bucket (escrow) by the CONTRACT earnings
		//    (gross - commission): a platform-funded promo discount does not
		//    reduce what the driver earns (§2.6 funding policy).
		creditTx, err := d.Ledger.Credit(ctx, ev.DriverID, driverNet, valueobjects.TxTypeRideCreditHeld, true, services.CreditOptions{
			IdempotencyKey: creditKey,
			ReferenceID:    &ev.RideID,
			ReferenceType:  "ride",
			Description:    fmt.Sprintf("Ride %s earning (held 72h)", rideStr),
		})
		if err != nil {
			return fmt.Errorf("ledger: driver held credit: %w", err)
		}

		// 3. Open the escrow hold (Phase F Step 1): release_after = now +
		//    configured window (default 72h) from the rules service.
		now := d.clock().Now()
		h, err := entities.NewEscrowHold(uuid.New(), ev.RideID, ev.RiderID, ev.DriverID, driverNet, now, d.escrowPolicy().Window())
		if err != nil {
			return err
		}
		h.CreditTxID = &creditTx.TxID
		if err := d.Escrows.Create(ctx, tx, h); err != nil {
			return fmt.Errorf("ledger: create escrow hold: %w", err)
		}
		hold = h

		return publish(ctx, tx, d, Event{
			Type:  "ledger.ride_settled",
			Topic: "nidaw.ledger",
			Payload: map[string]interface{}{
				"ride_id":       rideStr,
				"rider_id":      ev.RiderID.String(),
				"driver_id":     ev.DriverID.String(),
				"fare_cents":    payableCents,
				"fee_cents":     commissionCents,
				"held_cents":    driverNet.Cents(),
				"hold_id":       h.HoldID.String(),
				"release_after": h.ReleaseAfter.UTC().Format("2006-01-02T15:04:05Z"),
				// ---- Phase 3 authoritative settlement legs (integer ETB santim) --
				// Consumers (receipts, earnings surfaces, reconciliation jobs) read
				// these instead of re-deriving money from floats or trip actuals.
				"currency":                ContractCurrency,
				"payable_fare_santim":     payableCents,
				"commission_santim":       commissionCents,
				"driver_earnings_santim":  driverNet.Cents(),
				"tip_santim":              tipCents, // settled separately by the tip policy
				"settlement_idempotency":  idempotencyKey,
				"fare_snapshot_id":        snapshotID,
				"pending_cash_collection": pendingCash,
			},
			Timestamp: now.Unix(),
		})
	})
	if err != nil {
		return nil, err
	}
	log.Info("ride payment processed",
		zap.String("ride_id", rideStr),
		zap.Int64("payable_cents", payableCents),
		zap.Int64("commission_cents", commissionCents),
		zap.Int64("driver_credit_cents", driverNet.Cents()),
		zap.Int64("tip_cents", tipCents),
		zap.String("hold_id", hold.HoldID.String()))
	return hold, nil
}

// publish is a nil-safe helper for the outbox port.
func publish(ctx context.Context, tx services.DBTx, d *Deps, ev Event) error {
	if d.Events == nil {
		return nil
	}
	return d.Events.Publish(ctx, tx, ev)
}
