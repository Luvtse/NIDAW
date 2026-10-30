-- Rollback for 029_nidus_etb_standardization.sql.
--
-- Restores the pre-Phase-4 defaults on rides/payments and removes the ETB
-- CHECK constraints. It deliberately does NOT rewrite row data back to USD:
-- converting live ETB money rows to a currency the platform no longer
-- supports would fabricate historical state. Quarantined/cancelled legacy
-- rides remain cancelled (they had no valid fare snapshot and could never
-- settle anyway).

BEGIN;

ALTER TABLE rides DROP CONSTRAINT IF EXISTS rides_currency_etb_only;
ALTER TABLE rides ALTER COLUMN currency SET DEFAULT 'USD';

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_currency_etb_only;
ALTER TABLE payments ALTER COLUMN currency SET DEFAULT 'USD';

COMMIT;
