# Corpus typed booking contracts — 2026-10-24

## Scope

Introduced a version-1 domain contract parser for the policy-critical fields of each supported Corpus service type: rides, hotels, food, and freight. The create-booking command invokes this parser before policy evaluation or persistence, so malformed service data is rejected before it can be treated as policy compliant.

## Compatibility decision

The current Corpus API and `corporate_bookings.booking_data` column still use JSON objects. The typed contracts intentionally preserve extra fields in `RawPayload()` because the repository does not yet contain authoritative, product-owned request schemas for Nidus, Haven, Vorax, and Logix. This is an incremental validation boundary, not a claim that the downstream payloads are fully typed or compatible.

## Fields currently typed

- Rides: amount, fare, ride type, RFC3339 requested-at timestamp.
- Hotels: amount, price per night, non-negative integer star rating, chain.
- Food: amount and non-zero restaurant UUID.
- Freight: amount, shipment value, and non-zero carrier UUID.

All amount fields used for these contracts must be finite and non-negative. Unknown additional fields are retained to avoid silently dropping data.

## Validation

The parser has Go unit tests for typed ride decoding, preservation of extra fields, missing or invalid policy fields, and unsupported service types. `scripts/architecture/test-corpus-typed-booking-contracts.py` provides dependency-free static regression assertions.

The Go tests still need to be executed in an environment with the module dependencies available. This change does not claim full compilation, live PostgreSQL verification, or downstream consumer compatibility.
