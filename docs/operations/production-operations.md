# Production Operations

## Operational scope

This runbook covers routine operation of the Go API, product workflows, PostgreSQL, Redis, Kafka, Kong and supporting infrastructure configured in the repository. Exact production topology and alert thresholds must be set by the deployment environment; local Compose defaults are not production sizing guidance.

## Health and readiness

The API registers `/health` and `/ready` handlers in the Nidus router/server composition. Confirm their exact semantics in the current code before using them as load-balancer probes. A healthy process is not proof that payment providers, event consumers or every product workflow is healthy.

## Monitoring

Monitoring configuration is under `platform/monitoring/` and includes Prometheus, Alertmanager, Grafana dashboards, Loki/Promtail and Jaeger configuration. Validate scrape targets, retention, alert routing, access controls and dashboard accuracy in each environment.

Monitor at minimum:

- API request rate, latency, error rate and saturation;
- database connections, query latency, locks, replication and storage;
- Redis availability, memory/evictions and latency;
- Kafka broker health, consumer lag, failed deliveries and dead-letter queues where configured;
- payment authorization/capture/refund outcomes and reconciliation mismatches;
- ride dispatch/matching, booking/order lifecycle failures and outbox backlog;
- authentication failures, rate-limit activity and suspicious admin actions;
- backup freshness, restore test status and certificate/secret expiry.

## Logs and traces

Use structured logs and correlation/request IDs. Do not log passwords, access tokens, payment credentials, full card/bank data, private keys or unnecessary personal information. Restrict log and trace access and define retention according to legal and security requirements.

## Incident handling

1. Triage severity and customer impact.
2. Assign an incident lead and technical owner.
3. Preserve evidence and correlate request, trace, event and deployment IDs.
4. Mitigate safely; do not bypass payment, authorization or data-integrity controls.
5. Communicate through approved channels.
6. Recover service and validate business invariants.
7. Record root cause, impact, remediation and follow-up actions.

## Routine maintenance

- Review dependency/security updates and secret/certificate expiry.
- Verify backups and perform restore tests.
- Review database growth, indexes, query plans and connection pool saturation.
- Review Kafka retention, consumer lag and outbox backlog.
- Verify provider credentials and webhook delivery/reconciliation.
- Review privileged access and admin audit trails.
- Confirm alert ownership and runbook accuracy.

## Deployment restriction

Production deployment is currently blocked by `scripts/deploy.sh`; do not use this runbook to imply an approved production release path. See [deployment runbook](deployment-runbook.md).
