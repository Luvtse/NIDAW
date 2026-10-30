ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS onboarding_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (onboarding_status IN ('pending','approved','rejected','suspended')),
    ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
    ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS appeal_reason TEXT,
    ADD COLUMN IF NOT EXISTS appeal_status VARCHAR(20) NOT NULL DEFAULT 'none'
        CHECK (appeal_status IN ('none','pending','approved','rejected')),
    ADD COLUMN IF NOT EXISTS appeal_submitted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS onboarding_reviewed_by UUID REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS onboarding_reviewed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN ('drivers_license','vehicle_registration','insurance','background_check','vehicle_inspection','profile_photo')),
    name VARCHAR(160) NOT NULL,
    document_number VARCHAR(160),
    issue_date DATE,
    expiry_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected','expired')),
    mime_type VARCHAR(100) NOT NULL CHECK (mime_type IN ('application/pdf','image/jpeg','image/png')),
    content BYTEA NOT NULL,
    content_sha256 CHAR(64) NOT NULL,
    verification_notes TEXT,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (issue_date IS NULL OR expiry_date IS NULL OR expiry_date >= issue_date)
);
CREATE INDEX IF NOT EXISTS idx_driver_documents_driver_created ON driver_documents(driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_documents_review_queue ON driver_documents(status, created_at) WHERE status = 'pending';
