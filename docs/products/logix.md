# Logix — Freight and Logistics

## Scope

Logix is the domain for shipment lifecycle, carrier coordination, customs records and load matching.

## Current backend evidence

Code exists under `services/api/internal/modules/logix/`, including:

- shipment domain entity;
- customs application service;
- load-matching service;
- PostgreSQL repositories for carriers, customs and load-match events;
- an outbox dispatcher and load-match event repository.

## API and client status

The current server composition imports Logix PostgreSQL infrastructure but does not mount a Logix HTTP router. The gateway route directory also does not currently establish a complete reachable Logix API. Consumer client feature scaffolding exists under `apps/consumer_app/lib/features/logix/presentation/`.

Therefore, do not describe Logix as an externally usable or production-ready freight service. The current evidence supports domain/infrastructure implementation, not a complete exposed product workflow.

## Boundaries

Logix owns shipments, freight quotes, carrier coordination and shipment documents. It must not own payment execution or Corpus corporate approval state. Corpus must integrate through explicit Logix contracts once those are published and mounted.
