package commands

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/corpus/application/ports"
)

func TestDecisionDelegatesAuthenticatedApproverAndTrimmedNotes(t *testing.T) {
	repo := newBookingTestRepository()
	h := NewDecideCorporateBookingHandler(repo)
	bookingID, userID := uuid.New(), uuid.New()
	if err := h.Execute(context.Background(), bookingID, userID, true, "  approved for business travel  "); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if repo.decisions != 1 {
		t.Fatalf("expected one decision, got %d", repo.decisions)
	}
}

func TestDecisionRejectsMissingIdentityAndOversizedNotes(t *testing.T) {
	repo := newBookingTestRepository()
	h := NewDecideCorporateBookingHandler(repo)
	if err := h.Execute(context.Background(), uuid.New(), uuid.Nil, true, "ok"); err == nil {
		t.Fatal("expected missing approver identity to be rejected")
	}
	if err := h.Execute(context.Background(), uuid.New(), uuid.New(), true, string(make([]byte, 2001))); err == nil {
		t.Fatal("expected oversized notes to be rejected")
	}
	if repo.decisions != 0 {
		t.Fatalf("invalid decisions must not reach repository, got %d", repo.decisions)
	}
}

func TestDecisionPropagatesRepositoryError(t *testing.T) {
	repo := newBookingTestRepository()
	repo.decisionErr = ports.ErrBookingNotPending
	err := NewDecideCorporateBookingHandler(repo).Execute(context.Background(), uuid.New(), uuid.New(), false, "duplicate")
	if !errors.Is(err, ports.ErrBookingNotPending) {
		t.Fatalf("expected repository error to propagate, got %v", err)
	}
}
