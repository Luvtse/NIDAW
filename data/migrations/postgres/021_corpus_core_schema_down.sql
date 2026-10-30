-- Destructive rollback for 021_corpus_core_schema.sql.
-- Only use after explicitly confirming Corpus data may be discarded.
DROP TABLE IF EXISTS corporate_bookings;
DROP TABLE IF EXISTS travel_policies;
DROP TABLE IF EXISTS corporate_employees;
DROP TABLE IF EXISTS corporate_accounts;
