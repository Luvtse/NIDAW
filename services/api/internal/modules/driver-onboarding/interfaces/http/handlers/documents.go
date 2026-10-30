package handlers

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

const maxDriverDocumentBytes = 5 << 20

var allowedDocumentTypes = map[string]struct{}{
	"drivers_license":      {},
	"vehicle_registration": {},
	"insurance":            {},
	"background_check":     {},
	"vehicle_inspection":   {},
	"profile_photo":        {},
}

type DocumentsHandler struct{ db *database.Postgres }

func NewDocumentsHandler(db *database.Postgres) *DocumentsHandler { return &DocumentsHandler{db: db} }

type documentUploadRequest struct {
	Type           string `json:"type"`
	Name           string `json:"name"`
	DocumentNumber string `json:"document_number"`
	IssueDate      string `json:"issue_date"`
	ExpiryDate     string `json:"expiry_date"`
	ContentBase64  string `json:"content_base64"`
}

type documentDTO struct {
	ID                uuid.UUID  `json:"id"`
	DriverID          uuid.UUID  `json:"driver_id"`
	Type              string     `json:"type"`
	Name              string     `json:"name"`
	DocumentNumber    *string    `json:"document_number"`
	IssueDate         *time.Time `json:"issue_date"`
	ExpiryDate        *time.Time `json:"expiry_date"`
	Status            string     `json:"status"`
	FileURL           string     `json:"file_url"`
	VerificationNotes *string    `json:"verification_notes"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

func (h *DocumentsHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var driverID uuid.UUID
	if err := h.db.QueryRow(r.Context(), `SELECT id FROM drivers WHERE user_id=$1`, userID).Scan(&driverID); err != nil {
		documentError(w, http.StatusForbidden, "NOT_A_DRIVER")
		return
	}
	_, _ = h.db.Exec(r.Context(), `UPDATE driver_documents SET status='expired', updated_at=NOW() WHERE driver_id=$1 AND status IN ('pending','verified') AND expiry_date IS NOT NULL AND expiry_date < NOW()`, driverID)
	rows, err := h.db.Query(r.Context(), `SELECT id, driver_id, document_type, name, document_number, issue_date, expiry_date, status, verification_notes, created_at, updated_at FROM driver_documents WHERE driver_id=$1 ORDER BY created_at DESC`, driverID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "DOCUMENTS_UNAVAILABLE")
		return
	}
	defer rows.Close()
	docs := make([]documentDTO, 0)
	for rows.Next() {
		var d documentDTO
		var number, notes *string
		var issue, expiry *time.Time
		if err := rows.Scan(&d.ID, &d.DriverID, &d.Type, &d.Name, &number, &issue, &expiry, &d.Status, &notes, &d.CreatedAt, &d.UpdatedAt); err != nil {
			documentError(w, http.StatusInternalServerError, "DOCUMENTS_UNAVAILABLE")
			return
		}
		d.DocumentNumber, d.IssueDate, d.ExpiryDate, d.VerificationNotes = number, issue, expiry, notes
		d.FileURL = "/api/v1/nidus/drivers/documents/" + d.ID.String() + "/content"
		docs = append(docs, d)
	}
	if rows.Err() != nil {
		documentError(w, http.StatusInternalServerError, "DOCUMENTS_UNAVAILABLE")
		return
	}
	documentJSON(w, http.StatusOK, map[string]any{"documents": docs})
}

func (h *DocumentsHandler) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var driverID uuid.UUID
	if err := h.db.QueryRow(r.Context(), `SELECT id FROM drivers WHERE user_id=$1`, userID).Scan(&driverID); err != nil {
		documentError(w, http.StatusForbidden, "NOT_A_DRIVER")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxDriverDocumentBytes*2)
	var req documentUploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT")
		return
	}
	req.Type = strings.TrimSpace(strings.ToLower(req.Type))
	req.Name = strings.TrimSpace(req.Name)
	if _, valid := allowedDocumentTypes[req.Type]; !valid || req.Name == "" || len(req.Name) > 160 {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT_METADATA")
		return
	}
	content, err := base64.StdEncoding.DecodeString(req.ContentBase64)
	if err != nil || len(content) == 0 || len(content) > maxDriverDocumentBytes {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT_CONTENT")
		return
	}
	mimeType := detectDocumentMime(content)
	if mimeType == "" {
		documentError(w, http.StatusUnsupportedMediaType, "UNSUPPORTED_DOCUMENT_FORMAT")
		return
	}
	issue, err := parseOptionalDate(req.IssueDate)
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_ISSUE_DATE")
		return
	}
	expiry, err := parseOptionalDate(req.ExpiryDate)
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_EXPIRY_DATE")
		return
	}
	if issue != nil && expiry != nil && expiry.Before(*issue) {
		documentError(w, http.StatusBadRequest, "INVALID_DATE_RANGE")
		return
	}
	id := uuid.New()
	digest := sha256.Sum256(content)
	_, err = h.db.Exec(r.Context(), `INSERT INTO driver_documents (id, driver_id, document_type, name, document_number, issue_date, expiry_date, status, mime_type, content, content_sha256, created_at, updated_at) VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$7,'pending',$8,$9,$10,NOW(),NOW())`, id, driverID, req.Type, req.Name, strings.TrimSpace(req.DocumentNumber), issue, expiry, mimeType, content, hex.EncodeToString(digest[:]))
	if err != nil {
		documentError(w, http.StatusInternalServerError, "DOCUMENT_UPLOAD_FAILED")
		return
	}
	documentJSON(w, http.StatusCreated, map[string]any{"id": id, "driver_id": driverID, "type": req.Type, "name": req.Name, "document_number": strings.TrimSpace(req.DocumentNumber), "issue_date": issue, "expiry_date": expiry, "status": "pending", "file_url": "/api/v1/nidus/drivers/documents/" + id.String() + "/content", "created_at": time.Now().UTC(), "updated_at": time.Now().UTC()})
}

func (h *DocumentsHandler) Content(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT_ID")
		return
	}
	var content []byte
	var mimeType string
	err = h.db.QueryRow(r.Context(), `SELECT dd.content, dd.mime_type FROM driver_documents dd JOIN drivers d ON d.id=dd.driver_id WHERE dd.id=$1 AND d.user_id=$2`, id, userID).Scan(&content, &mimeType)
	if err != nil {
		documentError(w, http.StatusNotFound, "DOCUMENT_NOT_FOUND")
		return
	}
	w.Header().Set("Content-Type", mimeType)
	w.Header().Set("Content-Length", strconv.Itoa(len(content)))
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(content)
}

func (h *DocumentsHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT_ID")
		return
	}
	tag, err := h.db.Exec(r.Context(), `DELETE FROM driver_documents dd USING drivers d WHERE dd.id=$1 AND dd.driver_id=d.id AND d.user_id=$2 AND dd.status IN ('pending','rejected','expired')`, id, userID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "DOCUMENT_DELETE_FAILED")
		return
	}
	if tag.RowsAffected() == 0 {
		documentError(w, http.StatusConflict, "DOCUMENT_NOT_DELETABLE")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *DocumentsHandler) Review(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var role string
	if err := h.db.QueryRow(r.Context(), `SELECT role FROM users WHERE id=$1`, userID).Scan(&role); err != nil || (role != "admin" && role != "super_admin") {
		documentError(w, http.StatusForbidden, "ADMIN_REQUIRED")
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "documentID"))
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_DOCUMENT_ID")
		return
	}
	var req struct {
		Status string `json:"status"`
		Notes  string `json:"verification_notes"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req) != nil || (req.Status != "verified" && req.Status != "rejected") {
		documentError(w, http.StatusBadRequest, "INVALID_REVIEW")
		return
	}
	tag, err := h.db.Exec(r.Context(), `UPDATE driver_documents SET status=$2, verification_notes=NULLIF($3,''), reviewed_by=$4, reviewed_at=NOW(), updated_at=NOW() WHERE id=$1 AND status='pending' AND (expiry_date IS NULL OR expiry_date >= NOW())`, id, req.Status, strings.TrimSpace(req.Notes), userID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "DOCUMENT_REVIEW_FAILED")
		return
	}
	if tag.RowsAffected() != 1 {
		documentError(w, http.StatusConflict, "DOCUMENT_NOT_REVIEWABLE")
		return
	}
	var driverID uuid.UUID
	if err = h.db.QueryRow(r.Context(), `SELECT driver_id FROM driver_documents WHERE id=$1`, id).Scan(&driverID); err != nil {
		documentError(w, http.StatusNotFound, "DOCUMENT_NOT_FOUND")
		return
	}
	_, err = h.db.Exec(r.Context(), `UPDATE drivers SET license_verified=EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='drivers_license' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())), background_check=EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='background_check' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())), vehicle_inspected=EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='vehicle_inspection' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())), status=CASE WHEN status='available' AND (NOT EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='drivers_license' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())) OR NOT EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='background_check' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())) OR NOT EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='vehicle_inspection' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= NOW())) OR COALESCE(vehicle_type,'')='') THEN 'offline' ELSE status END, updated_at=NOW() WHERE id=$1`, driverID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "DRIVER_VERIFICATION_UPDATE_FAILED")
		return
	}
	documentJSON(w, http.StatusOK, map[string]any{"document_id": id, "status": req.Status})
}

func detectDocumentMime(b []byte) string {
	if len(b) >= 5 && string(b[:5]) == "%PDF-" {
		return "application/pdf"
	}
	if len(b) >= 8 && string(b[:8]) == "\x89PNG\r\n\x1a\n" {
		return "image/png"
	}
	if len(b) >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff {
		return "image/jpeg"
	}
	return ""
}

func parseOptionalDate(raw string) (*time.Time, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", raw)
	if err != nil {
		return nil, err
	}
	t = t.UTC()
	return &t, nil
}

func documentError(w http.ResponseWriter, status int, code string) {
	documentJSON(w, status, map[string]string{"error": code})
}
func documentJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (h *DocumentsHandler) Onboarding(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var result struct {
		DriverID         uuid.UUID `json:"driver_id"`
		Status           string    `json:"status"`
		SuspensionReason *string   `json:"suspension_reason"`
		AppealStatus     string    `json:"appeal_status"`
		AppealReason     *string   `json:"appeal_reason"`
		MissingDocuments []string  `json:"missing_documents"`
	}
	result.MissingDocuments = make([]string, 0)
	err := h.db.QueryRow(r.Context(), `SELECT id, onboarding_status, suspension_reason, appeal_status, appeal_reason FROM drivers WHERE user_id=$1`, userID).Scan(&result.DriverID, &result.Status, &result.SuspensionReason, &result.AppealStatus, &result.AppealReason)
	if err != nil {
		documentError(w, http.StatusForbidden, "NOT_A_DRIVER")
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT required.document_type FROM (VALUES ('drivers_license'),('background_check'),('vehicle_inspection'),('vehicle_registration'),('insurance')) AS required(document_type) WHERE NOT EXISTS (SELECT 1 FROM driver_documents d WHERE d.driver_id=$1 AND d.document_type=required.document_type AND d.status='verified' AND (d.expiry_date IS NULL OR d.expiry_date >= CURRENT_DATE))`, result.DriverID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "ONBOARDING_UNAVAILABLE")
		return
	}
	defer rows.Close()
	for rows.Next() {
		var missing string
		if rows.Scan(&missing) == nil {
			result.MissingDocuments = append(result.MissingDocuments, missing)
		}
	}
	if rows.Err() != nil {
		documentError(w, http.StatusInternalServerError, "ONBOARDING_UNAVAILABLE")
		return
	}
	documentJSON(w, http.StatusOK, result)
}

func (h *DocumentsHandler) Appeal(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var req struct {
		Reason string `json:"reason"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req) != nil {
		documentError(w, http.StatusBadRequest, "INVALID_APPEAL")
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if reason == "" || len(reason) > 2000 {
		documentError(w, http.StatusBadRequest, "INVALID_APPEAL_REASON")
		return
	}
	tag, err := h.db.Exec(r.Context(), `UPDATE drivers SET appeal_reason=$2, appeal_status='pending', appeal_submitted_at=NOW(), updated_at=NOW() WHERE user_id=$1 AND onboarding_status IN ('rejected','suspended')`, userID, reason)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "APPEAL_SUBMISSION_FAILED")
		return
	}
	if tag.RowsAffected() != 1 {
		documentError(w, http.StatusConflict, "APPEAL_NOT_AVAILABLE")
		return
	}
	documentJSON(w, http.StatusAccepted, map[string]string{"appeal_status": "pending"})
}

func (h *DocumentsHandler) ReviewDriver(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.GetUserIDFromContext(r.Context())
	if !ok {
		documentError(w, http.StatusUnauthorized, "UNAUTHORIZED")
		return
	}
	var role string
	if err := h.db.QueryRow(r.Context(), `SELECT role FROM users WHERE id=$1`, userID).Scan(&role); err != nil || (role != "admin" && role != "super_admin") {
		documentError(w, http.StatusForbidden, "ADMIN_REQUIRED")
		return
	}
	driverID, err := uuid.Parse(chi.URLParam(r, "driverID"))
	if err != nil {
		documentError(w, http.StatusBadRequest, "INVALID_DRIVER_ID")
		return
	}
	var req struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req) != nil {
		documentError(w, http.StatusBadRequest, "INVALID_REVIEW")
		return
	}
	if req.Decision != "approve" && req.Decision != "reject" && req.Decision != "suspend" {
		documentError(w, http.StatusBadRequest, "INVALID_DECISION")
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if req.Decision != "approve" && reason == "" {
		documentError(w, http.StatusBadRequest, "REASON_REQUIRED")
		return
	}
	if req.Decision == "approve" {
		var complete bool
		err = h.db.QueryRow(r.Context(), `SELECT COALESCE(vehicle_type,'') <> '' AND EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='drivers_license' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)) AND EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='background_check' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)) AND EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='vehicle_inspection' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)) AND EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='vehicle_registration' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)) AND EXISTS(SELECT 1 FROM driver_documents WHERE driver_id=$1 AND document_type='insurance' AND status='verified' AND (expiry_date IS NULL OR expiry_date >= CURRENT_DATE)) FROM drivers WHERE id=$1`, driverID).Scan(&complete)
		if err != nil || !complete {
			documentError(w, http.StatusConflict, "ONBOARDING_REQUIREMENTS_INCOMPLETE")
			return
		}
	}
	status := map[string]string{"approve": "approved", "reject": "rejected", "suspend": "suspended"}[req.Decision]
	var suspension any
	if req.Decision == "suspend" || req.Decision == "reject" {
		suspension = reason
	}
	tag, err := h.db.Exec(r.Context(), `UPDATE drivers SET onboarding_status=$2, suspension_reason=$3, suspended_at=CASE WHEN $2='suspended' THEN NOW() WHEN $2='approved' THEN NULL ELSE suspended_at END, onboarding_reviewed_by=$4, onboarding_reviewed_at=NOW(), appeal_status=CASE WHEN appeal_status='pending' THEN CASE WHEN $2='approved' THEN 'approved' ELSE 'rejected' END ELSE appeal_status END, status=CASE WHEN status='on_trip' THEN status ELSE 'offline' END, updated_at=NOW() WHERE id=$1`, driverID, status, suspension, userID)
	if err != nil {
		documentError(w, http.StatusInternalServerError, "ONBOARDING_REVIEW_FAILED")
		return
	}
	if tag.RowsAffected() != 1 {
		documentError(w, http.StatusNotFound, "DRIVER_NOT_FOUND")
		return
	}
	documentJSON(w, http.StatusOK, map[string]string{"driver_id": driverID.String(), "onboarding_status": status})
}
