# NIDAW master roadmap reconciliation

## Decision

The user-provided `NIDAW — MASTER IMPLEMENTATION PROMPT AND EXECUTION ROADMAP` supersedes the inconsistent phase labels in earlier progress notes. Phase numbers below refer only to that master roadmap.

## What was mislabeled

The earlier Phase 6 notes and Phase 7 archive treated ledger outbox implementation and its integration-test artifacts as if Phase 6/7 were consecutive implementation checkpoints. In the master roadmap, **Phase 6 is API contracts and cross-product integration**, while **Phase 7 is domain events, reliable messaging, and transactional outbox**. Therefore, the outbox source changes belong to Phase 7, not Phase 6.

## Evidence-based current status

- The repository contains `data/migrations/postgres/018_ledger_event_outbox.sql`, a ledger `EventBusPublisher` that writes using a caller-provided transaction, an `OutboxDispatcher`, startup wiring in `services/api/cmd/server/main.go`, unit tests, and environment-gated PostgreSQL integration-test artifacts.
- The integration tests have not been run against a real PostgreSQL database or Kafka in the available environment. The code and test artifacts do not establish production reliability.
- The dispatcher has at-least-once semantics: broker acknowledgement followed by process failure before marking the row published can redeliver. The event envelope currently does not propagate the outbox row's stable ID as an event ID, so a general event-ID-based deduplication contract is not demonstrated.
- The active-path audit explicitly says full provider webhook/top-up/payout/escrow event tracing is incomplete. Do not claim every relevant state transition atomically writes an outbox row until the transaction call paths are verified.
- The server has some explicit module wiring, but that alone does not satisfy Phase 8's complete composition-root acceptance criteria.
- Phase 6 acceptance is not demonstrated: the repository still needs a complete contract inventory, versioned cross-product API/event contracts, identified consumers, and compatibility/contract tests.
- Prerequisites Phases 3–5 are also only partially evidenced. Thus, Phase 7 work exists but cannot be accepted under the master roadmap until prerequisite gates are reviewed and passed.

## Required sequence from here

1. Re-establish the phase baseline against the master roadmap and correct any other stale phase labels.
2. Finish the Phase 0–2 blockers in dependency order, without treating the limited reversible-work review as full completion.
3. Complete Phase 3 domain ownership and enforceable dependency rules for Nidus, Haven, Vorax, Logix, Corpus, and shared capabilities.
4. Complete Phase 4 workflow invariants and Phase 5 database ownership/migration acceptance.
5. Complete Phase 6 contract inventory, versioning, consumer mapping, and contract validation.
6. Return to the existing Phase 7 outbox code, inspect it end-to-end, correct any reliability gaps, and execute the database/broker tests.
7. Only then proceed to Phase 8 runtime composition and later phases in the specified order.

## Status language

- **Implemented:** source changes or test artifacts are present.
- **Partially verified:** static inspection or local checks passed, but required integration evidence is missing.
- **Accepted:** all applicable phase acceptance criteria are evidenced. No claim is made here that Phases 0–7 are accepted in full.

No calendar estimates are included. No production-readiness claim is made.
