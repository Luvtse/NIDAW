package application

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ============================================================================
// RIDER ACTIVATION (Auth roadmap Phase 3)
//
// Activation = phone verified (permanent timestamp on users.phone_verified_at,
// written by the OTP flow) + every required legal agreement accepted against
// its CURRENT active version (user_consents, owned by the legal module).
// Optional profile fields (full name details, email, password, photo) are NOT
// part of activation: riders can book rides and order food with them empty.
//
// The required-agreement set is data-driven: legal_documents rows flagged
// requires_activation = true (migration 032). If an operator has not seeded
// any flag yet, we fall back to the canonical rider pair — terms_of_service
// and privacy_policy — so activation never deadlocks on missing metadata.
// ============================================================================

var (
	ErrActivationStore   = errors.New("activation store unavailable")
	ErrActivationUser    = errors.New("account not found for activation")
	ErrNoActiveDocument  = errors.New("no active legal document for type")
)

// defaultRequiredAgreements is the fallback rider activation set used only
// when no legal_documents row carries requires_activation = true.
var defaultRequiredAgreements = []string{"terms_of_service", "privacy_policy"}

// AgreementStatus is one required legal document rendered for the client's
// consent screen: what must be accepted, at which version, and whether the
// user already accepted that exact version.
type AgreementStatus struct {
	DocumentType    string     `json:"document_type"`
	Title           string     `json:"title"`
	Version         string     `json:"version"`
	Accepted        bool       `json:"accepted"`
	AcceptedAt      *time.Time `json:"accepted_at,omitempty"`
	AcceptedVersion *string    `json:"accepted_version,omitempty"`
	// Outdated is true when the user accepted an older version and the
	// document now requires re-consent.
	Outdated bool `json:"outdated"`
}

// ActivationStatus is the server-authoritative answer to "may this rider use
// the app?" plus the per-document checklist shown by the onboarding screen.
type ActivationStatus struct {
	Complete             bool              `json:"complete"`
	PhoneVerified        bool              `json:"phone_verified"`
	ActivatedAt          *time.Time        `json:"activated_at,omitempty"`
	RequiredAgreements   []AgreementStatus `json:"required_agreements"`
	MissingAgreements    []string          `json:"missing_agreements"`
	ProfileFieldsMissing []string          `json:"profile_fields_missing"`
}

// ActivationService reads/writes activation state on users and cross-checks
// consents against live legal_documents versions. It talks through the shared
// Postgres facade of the monolith — no second connection pool, no new infra.
type ActivationService struct {
	db   dbLike
	txer TxBeginner
}

// dbLike is the slice of database.Postgres this service needs; declaring it
// locally keeps the application package free of infrastructure imports and
// lets tests inject a fake.
type dbLike interface {
	Query(ctx context.Context, sql string, args ...interface{}) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...interface{}) pgx.Row
	Exec(ctx context.Context, sql string, args ...interface{}) (pgconn.CommandTag, error)
}

// TxBeginner is satisfied by *database.Postgres: activation flag flips run in
// a single transaction so consent checks and the durable record stay atomic.
type TxBeginner interface {
	Begin(ctx context.Context) (*database.Tx, error)
}

func NewActivationService(db dbLike) *ActivationService {
	return &ActivationService{db: db}
}

// WithTx enables transactional activation writes when the caller passes the
// concrete Postgres facade.
func (s *ActivationService) WithTx(t TxBeginner) *ActivationService {
	s.txer = t
	return s
}

// RequiredAgreementTypes resolves the activation-gating document types.
func (s *ActivationService) RequiredAgreementTypes(ctx context.Context) ([]string, error) {
	if s.db == nil {
		return nil, ErrActivationStore
	}
	rows, err := s.db.Query(ctx, `
		SELECT DISTINCT document_type
		FROM legal_documents
		WHERE is_active = true AND COALESCE(requires_activation, false)
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var types []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		types = append(types, t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(types) == 0 {
		types = append(types, defaultRequiredAgreements...)
	}
	return types, nil
}

// Status computes activation state for a user. DB errors propagate so
// callers fail closed (a rider is never shown as activated because a query
// hiccuped).
func (s *ActivationService) Status(ctx context.Context, userID uuid.UUID) (*ActivationStatus, error) {
	if s.db == nil {
		return nil, ErrActivationStore
	}

	var (
		onboardingComplete bool
		activatedAt        *time.Time
		phoneVerifiedAt    *time.Time
		fullName           *string
		email              *string
		passwordSet        bool
		profileImageSet    bool
		createdVia         *string
	)
	err := s.db.QueryRow(ctx, `
		SELECT onboarding_complete, activated_at, phone_verified_at,
		       full_name, email, (password_hash IS NOT NULL), (profile_image_url IS NOT NULL),
		       created_via
		FROM users WHERE id = $1
	`, userID).Scan(&onboardingComplete, &activatedAt, &phoneVerifiedAt,
		&fullName, &email, &passwordSet, &profileImageSet, &createdVia)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrActivationUser
	}
	if err != nil {
		return nil, err
	}

	reqTypes, err := s.RequiredAgreementTypes(ctx)
	if err != nil {
		return nil, err
	}

	st := &ActivationStatus{
		PhoneVerified: phoneVerifiedAt != nil,
		ActivatedAt:   activatedAt,
	}

	// One join resolves, per required type, both the current active document
	// and the user's stored consent (if any).
	for _, dt := range reqTypes {
		var (
			docID               string
			title, version      string
			requiresReconsent   bool
			ucGiven             bool
			ucAt                *time.Time
			ucVersion           *string
		)
		err := s.db.QueryRow(ctx, `
			SELECT ld.id, ld.title, ld.version, ld.requires_reconsent,
			       COALESCE(uc.consent_given, false), uc.consent_timestamp, uc.document_version
			FROM legal_documents ld
			LEFT JOIN user_consents uc ON uc.document_id = ld.id AND uc.user_id = $2
			WHERE ld.document_type = $1 AND ld.is_active = true
			ORDER BY ld.effective_date DESC
			LIMIT 1
		`, dt, userID).Scan(&docID, &title, &version, &requiresReconsent,
			&ucGiven, &ucAt, &ucVersion)
		if errors.Is(err, pgx.ErrNoRows) {
			// No active document seeded for this type: cannot gate on it.
			continue
		}
		if err != nil {
			return nil, err
		}
		ag := AgreementStatus{
			DocumentType:    dt,
			Title:           title,
			Version:         version,
			Accepted:        ucGiven && ucVersion != nil && *ucVersion == version,
			AcceptedAt:      ucAt,
			AcceptedVersion: ucVersion,
			Outdated:        ucGiven && requiresReconsent && ucVersion != nil && *ucVersion != version,
		}
		st.RequiredAgreements = append(st.RequiredAgreements, ag)
		if !ag.Accepted {
			st.MissingAgreements = append(st.MissingAgreements, dt)
		}
	}

	st.Complete = len(st.MissingAgreements) == 0 && st.PhoneVerified

	// users.onboarding_complete is the durable activation record. When the
	// computed truth and the stored flag disagree, the computation wins and
	// the flag is healed transactionally (guarded UPDATE + audit row).
	if st.Complete && !onboardingComplete {
		activated, err := s.markActivated(ctx, userID)
		if err != nil {
			return nil, err
		}
		if activated {
			var healed *time.Time
			_ = s.db.QueryRow(ctx, `SELECT activated_at FROM users WHERE id = $1`, userID).Scan(&healed)
			st.ActivatedAt = healed
		}
	} else if !st.Complete && onboardingComplete && createdVia != nil && *createdVia == "phone_otp" {
		// Phone-OTP account whose consent was withdrawn or rolled back to an
		// outdated version after activation: demote so apps re-gate honestly.
		if _, err := s.db.Exec(ctx, `
			UPDATE users SET onboarding_complete = false, updated_at = NOW()
			WHERE id = $1 AND onboarding_complete = true
		`, userID); err != nil {
			return nil, err
		}
		st.ActivatedAt = nil
	}

	// Informational only — these NEVER block Complete (Phase 3 rule: optional
	// profile fields must not gate ride booking or food ordering).
	if strings.TrimSpace(derefString(fullName)) == "" {
		st.ProfileFieldsMissing = append(st.ProfileFieldsMissing, "full_name")
	}
	if strings.TrimSpace(derefString(email)) == "" {
		st.ProfileFieldsMissing = append(st.ProfileFieldsMissing, "email")
	}
	if !passwordSet {
		st.ProfileFieldsMissing = append(st.ProfileFieldsMissing, "password")
	}
	if !profileImageSet {
		st.ProfileFieldsMissing = append(st.ProfileFieldsMissing, "profile_photo")
	}

	return st, nil
}

// Activate is the POST /api/v1/auth/onboarding/complete entry point. It
// recomputes activation from authoritative consent state; a direct call can
// therefore never mark an account active while required agreements are
// outstanding. Returns the final status (Complete=false => still gated).
func (s *ActivationService) Activate(ctx context.Context, userID uuid.UUID) (*ActivationStatus, error) {
	return s.Status(ctx, userID)
}

// markActivated flips the durable activation record inside one transaction:
// guarded UPDATE on users plus an audit row in consent_audit_log. Returns
// false when the row was already activated (concurrent double-submit).
func (s *ActivationService) markActivated(ctx context.Context, userID uuid.UUID) (bool, error) {
	if s.txer == nil {
		// No transaction source wired (unit-test fakes): fall back to the
		// same guarded statement without the audit row.
		tag, err := s.db.Exec(ctx, `
			UPDATE users
			SET onboarding_complete = true,
			    activated_at = COALESCE(activated_at, NOW()),
			    updated_at = NOW()
			WHERE id = $1 AND onboarding_complete = false
		`, userID)
		if err != nil {
			return false, err
		}
		return tag.RowsAffected() > 0, nil
	}

	tx, err := s.txer.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE users
		SET onboarding_complete = true,
		    activated_at = COALESCE(activated_at, NOW()),
		    updated_at = NOW()
		WHERE id = $1 AND onboarding_complete = false
	`, userID)
	if err != nil {
		return false, err
	}
	if tag.RowsAffected() == 0 {
		return false, nil // already activated concurrently — idempotent success
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO consent_audit_log (id, user_id, document_type, action, new_version, metadata)
		VALUES ($1, $2, 'account_activation', 'activation_completed', NULL, $3::jsonb)
	`, uuid.New(), userID, `{"source":"auth.onboarding.complete"}`)
	if err != nil {
		return false, err
	}

	if err := tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
}

func derefString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
