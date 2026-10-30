package services

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/domain/entities"
)

type carrierRepositoryStub struct {
	candidates []entities.Carrier
	byID       map[uuid.UUID]*entities.Carrier
	findErr    error
	getErr     error
}

func (s *carrierRepositoryStub) FindCandidateCarriers(context.Context, *entities.Load) ([]entities.Carrier, error) {
	return s.candidates, s.findErr
}
func (s *carrierRepositoryStub) GetCarrierByID(_ context.Context, id uuid.UUID) (*entities.Carrier, error) {
	if s.getErr != nil {
		return nil, s.getErr
	}
	return s.byID[id], nil
}

type loadMatchWriterStub struct {
	carrierID uuid.UUID
	score     float64
	err       error
	calls     int
}

func (s *loadMatchWriterStub) RecordLoadMatched(_ context.Context, _ *entities.Load, id uuid.UUID, score float64) error {
	s.calls++
	s.carrierID, s.score = id, score
	return s.err
}

func TestLoadMatcherRequiresRepository(t *testing.T) {
	matcher := NewLoadMatcher(nil, &loadMatchWriterStub{})
	_, err := matcher.FindBestCarrier(context.Background(), &entities.Load{ID: uuid.New()})
	if err == nil {
		t.Fatal("expected missing repository error")
	}
}

func TestLoadMatcherNoCandidatesDoesNotPublish(t *testing.T) {
	writer := &loadMatchWriterStub{}
	matcher := NewLoadMatcher(&carrierRepositoryStub{}, writer)
	_, err := matcher.FindBestCarrier(context.Background(), &entities.Load{ID: uuid.New()})
	if !errors.Is(err, ErrNoCarriersAvailable) {
		t.Fatalf("expected ErrNoCarriersAvailable, got %v", err)
	}
	if writer.calls != 0 {
		t.Fatalf("writer called %d times for no candidates", writer.calls)
	}
}

func TestLoadMatcherPersistsBestCandidateBeforeReturning(t *testing.T) {
	load := &entities.Load{ID: uuid.New(), EquipmentType: "dry_van", Origin: entities.Address{Country: "ET"}, Destination: entities.Address{Country: "KE"}, Rate: 500}
	low := entities.Carrier{ID: uuid.New(), CompanyName: "lower", OnTimeRate: .70, Rating: 3, EquipmentTypes: []string{"dry_van"}, ServiceAreas: []string{"ET"}}
	high := entities.Carrier{ID: uuid.New(), CompanyName: "higher", OnTimeRate: .98, Rating: 4.8, EquipmentTypes: []string{"dry_van"}, ServiceAreas: []string{"ET", "KE"}}
	writer := &loadMatchWriterStub{}
	repo := &carrierRepositoryStub{candidates: []entities.Carrier{low, high}, byID: map[uuid.UUID]*entities.Carrier{high.ID: &high}}
	matcher := NewLoadMatcher(repo, writer)
	got, err := matcher.FindBestCarrier(context.Background(), load)
	if err != nil {
		t.Fatalf("FindBestCarrier: %v", err)
	}
	if got == nil || got.ID != high.ID {
		t.Fatalf("expected highest-scoring carrier %s, got %#v", high.ID, got)
	}
	if writer.calls != 1 || writer.carrierID != high.ID {
		t.Fatalf("unexpected publication intent: %#v", writer)
	}
	if writer.score <= 0 || writer.score > 100 {
		t.Fatalf("score outside expected range: %v", writer.score)
	}
}

func TestLoadMatcherDoesNotReturnMatchWhenOutboxWriteFails(t *testing.T) {
	carrier := entities.Carrier{ID: uuid.New(), OnTimeRate: .9, Rating: 4, EquipmentTypes: []string{"dry_van"}, ServiceAreas: []string{"ET", "KE"}}
	writer := &loadMatchWriterStub{err: errors.New("outbox unavailable")}
	matcher := NewLoadMatcher(&carrierRepositoryStub{candidates: []entities.Carrier{carrier}, byID: map[uuid.UUID]*entities.Carrier{carrier.ID: &carrier}}, writer)
	got, err := matcher.FindBestCarrier(context.Background(), &entities.Load{ID: uuid.New(), EquipmentType: "dry_van", Origin: entities.Address{Country: "ET"}, Destination: entities.Address{Country: "KE"}})
	if err == nil {
		t.Fatal("expected outbox failure")
	}
	if got != nil {
		t.Fatalf("expected no successful result when outbox fails, got %#v", got)
	}
}

func TestLoadMatcherBreaksEqualScoresByCarrierID(t *testing.T) {
	load := &entities.Load{ID: uuid.New(), EquipmentType: "dry_van", Origin: entities.Address{Country: "ET"}, Destination: entities.Address{Country: "KE"}}
	firstID := uuid.MustParse("00000000-0000-4000-8000-000000000001")
	secondID := uuid.MustParse("00000000-0000-4000-8000-000000000002")
	first := entities.Carrier{ID: firstID, OnTimeRate: .9, Rating: 4, EquipmentTypes: []string{"dry_van"}, ServiceAreas: []string{"ET", "KE"}}
	second := entities.Carrier{ID: secondID, OnTimeRate: .9, Rating: 4, EquipmentTypes: []string{"dry_van"}, ServiceAreas: []string{"ET", "KE"}}
	writer := &loadMatchWriterStub{}
	matcher := NewLoadMatcher(&carrierRepositoryStub{candidates: []entities.Carrier{second, first}, byID: map[uuid.UUID]*entities.Carrier{firstID: &first, secondID: &second}}, writer)
	got, err := matcher.FindBestCarrier(context.Background(), load)
	if err != nil {
		t.Fatalf("FindBestCarrier: %v", err)
	}
	if got == nil || got.ID != firstID {
		t.Fatalf("expected stable UUID tie-break to select %s, got %#v", firstID, got)
	}
}
