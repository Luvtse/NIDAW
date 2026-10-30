package services

import (
	"context"
	"errors"
	"fmt"
	"math"
	"testing"
	"time"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/domain/entities"
)

type customsTariffStub struct {
	rate         float64
	exemptions   []string
	rateErr      error
	exemptionErr error
	calls        int
}

func (s *customsTariffStub) GetTariffRate(context.Context, string, string, string) (float64, error) {
	s.calls++
	return s.rate, s.rateErr
}

func (s *customsTariffStub) GetDutyExemptions(context.Context, string, string, string) ([]string, error) {
	s.calls++
	return s.exemptions, s.exemptionErr
}

type customsRepositoryStub struct {
	declaration       *CustomsDeclaration
	duties            float64
	err               error
	submissionCalls   int
	submissionID      string
	statusLookupCalls int
	statusUpdateCalls int
	updatedDuties     float64
	updatedTaxes      float64
}

func (s *customsRepositoryStub) SavePreparedDeclaration(_ context.Context, declaration *CustomsDeclaration, duties float64) error {
	s.declaration, s.duties = declaration, duties
	return s.err
}
func (s *customsRepositoryStub) MarkDeclarationSubmitted(_ context.Context, _, _ uuid.UUID, externalID string, _ time.Time) error {
	s.submissionCalls++
	s.submissionID = externalID
	return s.err
}
func (s *customsRepositoryStub) GetExternalDeclaration(context.Context, uuid.UUID) (string, uuid.UUID, error) {
	s.statusLookupCalls++
	return "external", uuid.New(), nil
}
func (s *customsRepositoryStub) UpdateDeclarationStatus(_ context.Context, _ uuid.UUID, _ uuid.UUID, _ entities.CustomsStatus, duties, taxes float64, _ *time.Time) error {
	s.statusUpdateCalls++
	s.updatedDuties, s.updatedTaxes = duties, taxes
	return nil
}

type customsAPIStub struct {
	externalID string
	err        error
	calls      int
	status     *CustomsStatus
}

func (s *customsAPIStub) SubmitDeclaration(context.Context, *CustomsDeclaration) (string, error) {
	s.calls++
	return s.externalID, s.err
}
func (s *customsAPIStub) GetDeclarationStatus(context.Context, string) (*CustomsStatus, error) {
	s.calls++
	return s.status, s.err
}

func TestPrepareDeclarationRejectsInvalidShipmentBeforeTariffLookup(t *testing.T) {
	cases := []struct {
		name     string
		shipment *entities.Shipment
	}{
		{name: "nil shipment", shipment: nil},
		{name: "zero packages", shipment: &entities.Shipment{HSCode: "1234", PackageCount: 0, OriginCountry: "ET", DestinationCountry: "KE"}},
		{name: "negative packages", shipment: &entities.Shipment{HSCode: "1234", PackageCount: -1, OriginCountry: "ET", DestinationCountry: "KE"}},
		{name: "nan declared value", shipment: &entities.Shipment{HSCode: "1234", PackageCount: 1, DeclaredValue: math.NaN(), OriginCountry: "ET", DestinationCountry: "KE"}},
		{name: "infinite declared value", shipment: &entities.Shipment{HSCode: "1234", PackageCount: 1, DeclaredValue: math.Inf(1), OriginCountry: "ET", DestinationCountry: "KE"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tariff := &customsTariffStub{rate: 10}
			service := NewCustomsService(&customsRepositoryStub{}, nil, nil, tariff)
			if _, err := service.PrepareDeclaration(context.Background(), tc.shipment); err == nil {
				t.Fatal("expected invalid shipment to be rejected")
			}
			if tariff.calls != 0 {
				t.Fatalf("tariff lookup called %d times for invalid shipment", tariff.calls)
			}
		})
	}
}

func TestPrepareDeclarationFailsClosedWhenExemptionLookupFails(t *testing.T) {
	tariff := &customsTariffStub{rate: 10, exemptionErr: errors.New("tariff source unavailable")}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, nil, tariff)
	shipment := &entities.Shipment{
		ID: uuid.New(), HSCode: "1234", PackageCount: 2, DeclaredValue: 100,
		OriginCountry: "ET", DestinationCountry: "KE",
	}
	if _, err := service.PrepareDeclaration(context.Background(), shipment); err == nil {
		t.Fatal("expected exemption lookup failure")
	}
	if repository.declaration != nil {
		t.Fatal("declaration persisted despite exemption lookup failure")
	}
}

func TestPrepareDeclarationPersistsCalculatedDuties(t *testing.T) {
	tariff := &customsTariffStub{rate: 10}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, nil, tariff)
	shipment := &entities.Shipment{
		ID: uuid.New(), HSCode: "1234", PackageCount: 2, DeclaredValue: 100,
		OriginCountry: "ET", DestinationCountry: "KE",
	}
	declaration, err := service.PrepareDeclaration(context.Background(), shipment)
	if err != nil {
		t.Fatalf("PrepareDeclaration() error = %v", err)
	}
	if declaration.Items[0].UnitPrice != 50 {
		t.Fatalf("unit price = %v, want 50", declaration.Items[0].UnitPrice)
	}
	if repository.duties != 10 {
		t.Fatalf("persisted duties = %v, want 10", repository.duties)
	}
	if repository.declaration != declaration {
		t.Fatal("repository did not receive the created declaration")
	}
}

func TestPrepareDeclarationRejectsInvalidTariffRatesWithoutPersistence(t *testing.T) {
	for _, rate := range []float64{math.NaN(), math.Inf(1), math.Inf(-1), -0.01} {
		t.Run(fmt.Sprint(rate), func(t *testing.T) {
			tariff := &customsTariffStub{rate: rate}
			repository := &customsRepositoryStub{}
			service := NewCustomsService(repository, nil, nil, tariff)
			shipment := &entities.Shipment{ID: uuid.New(), HSCode: "1234", PackageCount: 1, DeclaredValue: 100, OriginCountry: "ET", DestinationCountry: "KE"}
			if _, err := service.PrepareDeclaration(context.Background(), shipment); err == nil {
				t.Fatal("expected invalid tariff rate to be rejected")
			}
			if repository.declaration != nil {
				t.Fatal("declaration persisted with invalid tariff rate")
			}
		})
	}
}

func TestPrepareDeclarationDoesNotInventExemptionReduction(t *testing.T) {
	tariff := &customsTariffStub{rate: 10, exemptions: []string{"FTA"}}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, nil, tariff)
	shipment := &entities.Shipment{ID: uuid.New(), HSCode: "1234", PackageCount: 1, DeclaredValue: 100, OriginCountry: "ET", DestinationCountry: "KE"}
	if _, err := service.PrepareDeclaration(context.Background(), shipment); err == nil {
		t.Fatal("expected an exemption without a calculation policy to fail closed")
	}
	if repository.declaration != nil {
		t.Fatal("declaration persisted despite unresolved exemption calculation")
	}
}

func TestPrepareDeclarationRejectsDutyOverflowWithoutPersistence(t *testing.T) {
	tariff := &customsTariffStub{rate: math.MaxFloat64}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, nil, tariff)
	shipment := &entities.Shipment{ID: uuid.New(), HSCode: "1234", PackageCount: 1, DeclaredValue: math.MaxFloat64, OriginCountry: "ET", DestinationCountry: "KE"}
	if _, err := service.PrepareDeclaration(context.Background(), shipment); err == nil {
		t.Fatal("expected overflowing duty calculation to be rejected")
	}
	if repository.declaration != nil {
		t.Fatal("declaration persisted with overflowing duty calculation")
	}
}

func TestMapStatusRejectsUnknownExternalValues(t *testing.T) {
	if _, err := mapStatus("mystery-status"); err == nil {
		t.Fatal("expected unsupported status to fail closed")
	}
}

func TestSubmitDeclarationRejectsMissingIDsBeforeExternalCall(t *testing.T) {
	api := &customsAPIStub{externalID: "external-1"}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, api, nil)
	declaration := &CustomsDeclaration{ID: uuid.New(), ShipmentID: uuid.Nil}
	if err := service.SubmitDeclaration(context.Background(), declaration); err == nil {
		t.Fatal("expected missing shipment ID to be rejected")
	}
	if api.calls != 0 || repository.submissionCalls != 0 {
		t.Fatalf("unexpected side effects: API calls=%d repository calls=%d", api.calls, repository.submissionCalls)
	}
}

func TestSubmitDeclarationRejectsEmptyExternalIDWithoutPersistence(t *testing.T) {
	api := &customsAPIStub{externalID: "  "}
	repository := &customsRepositoryStub{}
	service := NewCustomsService(repository, nil, api, nil)
	declaration := &CustomsDeclaration{ID: uuid.New(), ShipmentID: uuid.New()}
	if err := service.SubmitDeclaration(context.Background(), declaration); err == nil {
		t.Fatal("expected empty external declaration ID to be rejected")
	}
	if repository.submissionCalls != 0 {
		t.Fatal("repository called with empty external declaration ID")
	}
}

func TestSubmitDeclarationPropagatesPersistenceFailure(t *testing.T) {
	api := &customsAPIStub{externalID: "external-1"}
	repository := &customsRepositoryStub{err: errors.New("database unavailable")}
	service := NewCustomsService(repository, nil, api, nil)
	declaration := &CustomsDeclaration{ID: uuid.New(), ShipmentID: uuid.New()}
	if err := service.SubmitDeclaration(context.Background(), declaration); err == nil {
		t.Fatal("expected persistence failure")
	}
	if api.calls != 1 || repository.submissionCalls != 1 || repository.submissionID != "external-1" {
		t.Fatalf("unexpected submission flow: API calls=%d repository calls=%d external ID=%q", api.calls, repository.submissionCalls, repository.submissionID)
	}
}

func TestPollDeclarationStatusRejectsNilIDBeforeRepositoryLookup(t *testing.T) {
	repository := &customsRepositoryStub{}
	api := &customsAPIStub{}
	service := NewCustomsService(repository, nil, api, nil)
	if err := service.PollDeclarationStatus(context.Background(), uuid.Nil); err == nil {
		t.Fatal("expected nil declaration ID to be rejected")
	}
	if repository.statusLookupCalls != 0 || api.calls != 0 {
		t.Fatalf("unexpected side effects: repository lookups=%d API calls=%d", repository.statusLookupCalls, api.calls)
	}
}

func TestPollDeclarationStatusRejectsInvalidAmountsBeforePersistence(t *testing.T) {
	cases := []struct {
		name   string
		duties float64
		taxes  float64
	}{
		{name: "negative duties", duties: -1, taxes: 0},
		{name: "nan duties", duties: math.NaN(), taxes: 0},
		{name: "infinite duties", duties: math.Inf(1), taxes: 0},
		{name: "negative taxes", duties: 0, taxes: -1},
		{name: "nan taxes", duties: 0, taxes: math.NaN()},
		{name: "infinite taxes", duties: 0, taxes: math.Inf(1)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repository := &customsRepositoryStub{}
			api := &customsAPIStub{status: &CustomsStatus{Status: "pending", DutiesOwed: tc.duties, TaxesOwed: tc.taxes}}
			service := NewCustomsService(repository, nil, api, nil)
			if err := service.PollDeclarationStatus(context.Background(), uuid.New()); err == nil {
				t.Fatal("expected invalid external amounts to be rejected")
			}
			if api.calls != 1 {
				t.Fatalf("authority calls = %d, want 1", api.calls)
			}
			if repository.statusUpdateCalls != 0 {
				t.Fatalf("status updates = %d, want 0", repository.statusUpdateCalls)
			}
		})
	}
}

func TestPollDeclarationStatusPersistsValidAmounts(t *testing.T) {
	repository := &customsRepositoryStub{}
	api := &customsAPIStub{status: &CustomsStatus{Status: "pending", DutiesOwed: 12.5, TaxesOwed: 2.5}}
	service := NewCustomsService(repository, nil, api, nil)
	if err := service.PollDeclarationStatus(context.Background(), uuid.New()); err != nil {
		t.Fatalf("PollDeclarationStatus() error = %v", err)
	}
	if repository.statusUpdateCalls != 1 || repository.updatedDuties != 12.5 || repository.updatedTaxes != 2.5 {
		t.Fatalf("unexpected persisted status: calls=%d duties=%v taxes=%v", repository.statusUpdateCalls, repository.updatedDuties, repository.updatedTaxes)
	}
}
