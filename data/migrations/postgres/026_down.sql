DROP TABLE IF EXISTS driver_documents;
ALTER TABLE drivers
    DROP COLUMN IF EXISTS onboarding_reviewed_at,
    DROP COLUMN IF EXISTS onboarding_reviewed_by,
    DROP COLUMN IF EXISTS appeal_submitted_at,
    DROP COLUMN IF EXISTS appeal_status,
    DROP COLUMN IF EXISTS appeal_reason,
    DROP COLUMN IF EXISTS suspended_at,
    DROP COLUMN IF EXISTS suspension_reason,
    DROP COLUMN IF EXISTS onboarding_status;
