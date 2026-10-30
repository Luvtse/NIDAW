-- Corpus corporate booking persistence.
-- These tables are intentionally owned by Corpus; product-specific bookings
-- remain in Nidus, Haven, Vorax, and Logix and are reached through events.

CREATE TABLE IF NOT EXISTS corporate_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name VARCHAR(255) NOT NULL,
    tax_id VARCHAR(100) NOT NULL DEFAULT '',
    billing_email VARCHAR(255) NOT NULL DEFAULT '',
    account_manager VARCHAR(255) NOT NULL DEFAULT '',
    tier VARCHAR(32) NOT NULL DEFAULT 'business'
        CHECK (tier IN ('startup', 'business', 'enterprise')),
    credit_limit NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0),
    current_balance NUMERIC(14,2) NOT NULL DEFAULT 0,
    currency CHAR(3) NOT NULL DEFAULT 'ETB',
    employee_count INTEGER NOT NULL DEFAULT 0 CHECK (employee_count >= 0),
    enabled_services TEXT[] NOT NULL DEFAULT ARRAY['rides']::TEXT[],
    status VARCHAR(32) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('active', 'suspended', 'pending')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS corporate_employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    corporate_id UUID NOT NULL REFERENCES corporate_accounts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    employee_id VARCHAR(128) NOT NULL,
    department VARCHAR(255) NOT NULL DEFAULT '',
    role VARCHAR(64) NOT NULL DEFAULT 'employee',
    manager_id UUID REFERENCES corporate_employees(id) ON DELETE SET NULL,
    spending_limit NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (spending_limit >= 0),
    approval_level INTEGER NOT NULL DEFAULT 0 CHECK (approval_level >= 0),
    status VARCHAR(32) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (corporate_id, employee_id),
    UNIQUE (corporate_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_corporate_employees_approver
    ON corporate_employees (corporate_id, approval_level, id)
    WHERE status = 'active' AND manager_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS travel_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    corporate_id UUID NOT NULL REFERENCES corporate_accounts(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    ride_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    hotel_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    food_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    freight_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    approval_rules JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT false,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (corporate_id, version)
);
CREATE INDEX IF NOT EXISTS idx_travel_policies_active
    ON travel_policies (corporate_id, effective_from DESC)
    WHERE is_active = true;

CREATE TABLE IF NOT EXISTS corporate_bookings (
    id UUID PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES corporate_employees(id) ON DELETE RESTRICT,
    corporate_id UUID NOT NULL REFERENCES corporate_accounts(id) ON DELETE RESTRICT,
    service_type VARCHAR(32) NOT NULL CHECK (service_type IN ('rides', 'hotels', 'food', 'freight')),
    booking_data JSONB NOT NULL,
    payment_method VARCHAR(40) NOT NULL DEFAULT 'corporate_account'
        CHECK (payment_method IN ('corporate_account', 'personal_reimbursement', 'split')),
    status VARCHAR(32) NOT NULL CHECK (status IN ('confirmed', 'pending_approval', 'rejected', 'cancelled')),
    policy_compliant BOOLEAN NOT NULL,
    violations TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    estimated_amount NUMERIC(14,2) NOT NULL CHECK (estimated_amount >= 0),
    requires_approval BOOLEAN NOT NULL DEFAULT false,
    approver_id UUID REFERENCES corporate_employees(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (status <> 'pending_approval' OR approver_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_corporate_bookings_employee_created
    ON corporate_bookings (employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_corporate_bookings_corporate_status
    ON corporate_bookings (corporate_id, status, created_at DESC);
