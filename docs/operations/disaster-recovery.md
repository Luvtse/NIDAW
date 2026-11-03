# Disaster Recovery

## Purpose and current status

This document defines the minimum recovery procedure for NIDAW. The repository contains PostgreSQL and TimescaleDB migration assets, Redis/Kafka/MinIO Compose services and infrastructure configuration. The presence of these assets is not evidence that production backups, cross-region replication or tested recovery objectives are currently operational.

**Production RPO/RTO values must be approved by the service owner and validated through restore exercises. Do not publish unverified numeric guarantees.**

## Recovery priorities

1. Establish incident command and identify the affected environment/region.
2. Stop unsafe writes or isolate compromised infrastructure where necessary.
3. Preserve available logs, metrics, database snapshots and deployment/configuration metadata.
4. Determine the last known consistent database and object-storage recovery points.
5. Restore dependencies in order: network/secrets, database, object storage, cache, messaging, API and clients.
6. Validate data integrity and replay only events whose idempotency and ordering semantics are understood.
7. Re-enable traffic gradually and monitor critical workflows.

## PostgreSQL recovery

- Identify the approved backup/snapshot and its timestamp.
- Restore into an isolated target first; never overwrite the only surviving copy.
- Apply only the migration state compatible with the selected application release.
- Verify migration history, row counts, critical constraints and financial ledger invariants.
- Validate ride, booking, order, corporate booking and payment records with their owning services.
- Promote the restored database only after owner approval.

## Redis recovery

Redis is a cache/session/realtime dependency. Determine which keys are reconstructible and which contain state that must be recovered from an authoritative store. Do not assume a Redis snapshot is a substitute for PostgreSQL business records.

## Kafka recovery

Verify broker health, topic configuration, retention and consumer offsets. Replay only after confirming event schema compatibility, consumer idempotency and the effect on downstream state. Avoid duplicate financial postings by validating event IDs and ledger idempotency records.

## Object storage recovery

Restore required MinIO/S3 objects and verify bucket policy, encryption keys, object checksums and application references. A backup is unusable if its encryption key is unavailable.

## Recovery validation

Before reopening the environment, verify API health/readiness, authentication, database connectivity, event processing, payment reconciliation, driver/rider critical workflows, booking/order integrity, file access and observability. Record actual recovery duration and data-loss window; use these results to set approved RTO/RPO targets.

## Exercises and ownership

Run scheduled restore exercises in an isolated environment. Record the tested backup, restore steps, measured RTO/RPO, failures and corrective actions in the operational incident record. Assign named operational ownership outside this document; never invent on-call contacts or escalation addresses here.
