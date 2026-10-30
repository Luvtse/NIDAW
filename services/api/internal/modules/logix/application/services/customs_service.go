package services

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/domain/entities"
	"nidaw-backend/internal/shared/eventbus"
)

type CustomsRepository interface {
	SavePreparedDeclaration(ctx context.Context, declaration *CustomsDeclaration, calculatedDuties float64) error
	MarkDeclarationSubmitted(ctx context.Context, declarationID, shipmentID uuid.UUID, externalID string, submittedAt time.Time) error
	GetExternalDeclaration(ctx context.Context, declarationID uuid.UUID) (string, uuid.UUID, error)
	UpdateDeclarationStatus(ctx context.Context, declarationID, shipmentID uuid.UUID, status entities.CustomsStatus, dutiesOwed, taxesOwed float64, clearanceDate *time.Time) error
}

type CustomsService struct {
	repository CustomsRepository
	bus        eventbus.EventBus
	customsAPI CustomsAPI
	tariffDB   TariffDatabase
}

func NewCustomsService(repository CustomsRepository, bus eventbus.EventBus, api CustomsAPI, tariff TariffDatabase) *CustomsService {
	return &CustomsService{
		repository: repository,
		bus:        bus,
		customsAPI: api,
		tariffDB:   tariff,
	}
}

type CustomsAPI interface {
	SubmitDeclaration(ctx context.Context, declaration *CustomsDeclaration) (string, error)
	GetDeclarationStatus(ctx context.Context, declarationID string) (*CustomsStatus, error)
}

type TariffDatabase interface {
	GetTariffRate(ctx context.Context, hsCode, originCountry, destCountry string) (float64, error)
	GetDutyExemptions(ctx context.Context, hsCode, originCountry, destCountry string) ([]string, error)
}

type CustomsDeclaration struct {
	ID                 uuid.UUID         `json:"id"`
	ShipmentID         uuid.UUID         `json:"shipment_id"`
	ImporterID         uuid.UUID         `json:"importer_id"`
	ExporterID         uuid.UUID         `json:"exporter_id"`
	OriginCountry      string            `json:"origin_country"`
	DestinationCountry string            `json:"destination_country"`
	Items              []CustomsItem     `json:"items"`
	TotalValue         float64           `json:"total_value"`
	Currency           string            `json:"currency"`
	Incoterm           string            `json:"incoterm"` // EXW, FOB, CIF, DDP, etc.
	Documents          []CustomsDocument `json:"documents"`
}

type CustomsItem struct {
	HSCode        string  `json:"hs_code"`
	Description   string  `json:"description"`
	Quantity      int     `json:"quantity"`
	UnitPrice     float64 `json:"unit_price"`
	TotalValue    float64 `json:"total_value"`
	WeightKg      float64 `json:"weight_kg"`
	OriginCountry string  `json:"origin_country"`
}

type CustomsDocument struct {
	Type      string    `json:"type"` // commercial_invoice, packing_list, bill_of_lading, certificate_of_origin
	URL       string    `json:"url"`
	IssueDate time.Time `json:"issue_date"`
}

type CustomsStatus struct {
	DeclarationID string     `json:"declaration_id"`
	Status        string     `json:"status"`
	DutiesOwed    float64    `json:"duties_owed"`
	TaxesOwed     float64    `json:"taxes_owed"`
	ClearanceDate *time.Time `json:"clearance_date"`
	HoldReason    string     `json:"hold_reason"`
}

func (s *CustomsService) PrepareDeclaration(ctx context.Context, shipment *entities.Shipment) (*CustomsDeclaration, error) {
	// 1. Validate required data before calculating per-package values.
	if shipment == nil {
		return nil, errors.New("shipment is required for customs clearance")
	}
	if shipment.HSCode == "" {
		return nil, errors.New("HS code is required for customs clearance")
	}
	if shipment.PackageCount <= 0 {
		return nil, errors.New("package count must be greater than zero for customs clearance")
	}
	if math.IsNaN(shipment.DeclaredValue) || math.IsInf(shipment.DeclaredValue, 0) || shipment.DeclaredValue < 0 {
		return nil, errors.New("declared value must be a finite non-negative amount")
	}
	if shipment.OriginCountry == "" || shipment.DestinationCountry == "" {
		return nil, errors.New("origin and destination countries are required for customs clearance")
	}
	if shipment.OriginCountry == shipment.DestinationCountry {
		return nil, errors.New("domestic shipments do not require customs")
	}

	// 2. Build declaration
	declaration := &CustomsDeclaration{
		ID:                 uuid.New(),
		ShipmentID:         shipment.ID,
		ImporterID:         shipment.ConsigneeID,
		ExporterID:         shipment.ShipperID,
		OriginCountry:      shipment.OriginCountry,
		DestinationCountry: shipment.DestinationCountry,
		TotalValue:         shipment.DeclaredValue,
		Currency:           shipment.Currency,
		Incoterm:           "CIF", // Default
		Items: []CustomsItem{
			{
				HSCode:        shipment.HSCode,
				Description:   shipment.CargoDescription,
				Quantity:      shipment.PackageCount,
				UnitPrice:     shipment.DeclaredValue / float64(shipment.PackageCount),
				TotalValue:    shipment.DeclaredValue,
				WeightKg:      shipment.WeightKg,
				OriginCountry: shipment.OriginCountry,
			},
		},
	}

	// 3. Calculate duties and taxes
	if s.tariffDB == nil {
		return nil, errors.New("tariff database is not configured")
	}
	dutyRate, err := s.tariffDB.GetTariffRate(ctx, shipment.HSCode, shipment.OriginCountry, shipment.DestinationCountry)
	if err != nil {
		return nil, fmt.Errorf("failed to get tariff rate: %w", err)
	}
	if math.IsNaN(dutyRate) || math.IsInf(dutyRate, 0) || dutyRate < 0 {
		return nil, errors.New("tariff rate must be a finite non-negative percentage")
	}

	duties := shipment.DeclaredValue * (dutyRate / 100.0)
	if math.IsNaN(duties) || math.IsInf(duties, 0) || duties < 0 {
		return nil, errors.New("calculated customs duties must be finite and non-negative")
	}

	// An exemption lookup returns identifiers, not an applicable rate or a
	// calculation decision. Do not invent a universal reduction percentage:
	// until the tariff source provides an explicit, auditable exemption policy,
	// fail closed rather than persisting a potentially incorrect duty amount.
	exemptions, err := s.tariffDB.GetDutyExemptions(ctx, shipment.HSCode, shipment.OriginCountry, shipment.DestinationCountry)
	if err != nil {
		return nil, fmt.Errorf("failed to get duty exemptions: %w", err)
	}
	if len(exemptions) > 0 {
		return nil, errors.New("applicable customs exemptions require an explicit calculation policy")
	}

	// 4. Save declaration to database
	if s.repository == nil {
		return nil, errors.New("customs repository is not configured")
	}
	if err := s.repository.SavePreparedDeclaration(ctx, declaration, duties); err != nil {
		return nil, fmt.Errorf("save prepared customs declaration: %w", err)
	}

	return declaration, nil
}

func (s *CustomsService) SubmitDeclaration(ctx context.Context, declaration *CustomsDeclaration) error {
	if declaration == nil {
		return errors.New("customs declaration is required")
	}
	if declaration.ID == uuid.Nil || declaration.ShipmentID == uuid.Nil {
		return errors.New("customs declaration and shipment IDs are required")
	}
	if s.customsAPI == nil {
		return errors.New("customs authority API is not configured")
	}
	if s.repository == nil {
		return errors.New("customs repository is not configured")
	}
	// 1. Submit to customs authority API
	externalID, err := s.customsAPI.SubmitDeclaration(ctx, declaration)
	if err != nil {
		return fmt.Errorf("submit customs declaration to authority: %w", err)
	}
	if strings.TrimSpace(externalID) == "" {
		return errors.New("customs authority returned an empty external declaration ID")
	}

	// Keep declaration and shipment state changes in one repository transaction.
	// If this persistence step fails after external acceptance, the external
	// submission may already exist; retry safety depends on authority-side
	// idempotency/reconciliation and must not be assumed here.
	if err := s.repository.MarkDeclarationSubmitted(ctx, declaration.ID, declaration.ShipmentID, externalID, time.Now().UTC()); err != nil {
		return fmt.Errorf("persist customs submission: %w", err)
	}

	return nil
}

func (s *CustomsService) PollDeclarationStatus(ctx context.Context, declarationID uuid.UUID) error {
	if declarationID == uuid.Nil {
		return errors.New("customs declaration ID is required")
	}
	if s.repository == nil {
		return errors.New("customs repository is not configured")
	}
	// Read the external reference through the persistence port.
	externalID, shipmentID, err := s.repository.GetExternalDeclaration(ctx, declarationID)
	if err != nil {
		return fmt.Errorf("load external customs declaration: %w", err)
	}

	// Poll customs API
	if s.customsAPI == nil {
		return errors.New("customs authority API is not configured")
	}
	status, err := s.customsAPI.GetDeclarationStatus(ctx, externalID)
	if err != nil {
		return fmt.Errorf("query customs authority status for external declaration %q: %w", externalID, err)
	}
	if status == nil {
		return errors.New("customs authority returned an empty status")
	}
	if math.IsNaN(status.DutiesOwed) || math.IsInf(status.DutiesOwed, 0) || status.DutiesOwed < 0 ||
		math.IsNaN(status.TaxesOwed) || math.IsInf(status.TaxesOwed, 0) || status.TaxesOwed < 0 {
		return errors.New("customs authority returned duties or taxes that are not finite non-negative amounts")
	}

	// Validate the external response before allowing it to mutate local state.
	newStatus, err := mapStatus(status.Status)
	if err != nil {
		return fmt.Errorf("map customs authority status: %w", err)
	}
	if err := s.repository.UpdateDeclarationStatus(ctx, declarationID, shipmentID, newStatus, status.DutiesOwed, status.TaxesOwed, status.ClearanceDate); err != nil {
		return fmt.Errorf("persist customs status: %w", err)
	}

	return nil
}

func mapStatus(apiStatus string) (entities.CustomsStatus, error) {
	switch apiStatus {
	case "pending":
		return entities.CustomsPending, nil
	case "under_review":
		return entities.CustomsUnderReview, nil
	case "cleared":
		return entities.CustomsCleared, nil
	case "held":
		return entities.CustomsHeld, nil
	case "rejected":
		return entities.CustomsRejected, nil
	default:
		return "", fmt.Errorf("unsupported customs status %q", apiStatus)
	}
}
