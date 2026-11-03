# Corpus — Corporate Travel Management

## Scope

Corpus owns corporate accounts, corporate booking requests, policy/approval decisions and orchestration state. It must coordinate product capabilities through explicit contracts rather than owning their private operational data.

## Current backend evidence

Implementation is under `services/api/internal/modules/corpus/`. Its HTTP router is mounted by the API composition root and exposes protected booking operations under `/api/v1/corpus`:

- `POST /bookings`
- `POST /bookings/{bookingID}/approve`
- `POST /bookings/{bookingID}/reject`

The module contains application commands, booking repository interfaces, domain policy evaluation and PostgreSQL persistence/outbox adapters.

## Current client evidence

Consumer app Corpus feature presentation code exists under `apps/consumer_app/lib/features/corpus/`.

## Boundaries and limitations

Corpus owns corporate policy, approvals, budgets and its orchestration records. It must not import Nidus/Haven/Vorax/Logix private implementation packages or mutate their private tables. The currently mounted booking endpoints do not establish complete integrations for every travel product, enterprise tenant administration, invoicing or policy coverage. Verify each product adapter and contract before enabling a corporate workflow.
