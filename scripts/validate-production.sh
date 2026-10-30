#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-nidaw-production}"
RELEASE="${HELM_RELEASE:-nidaw-production}"
API_HEALTH_URL="${API_HEALTH_URL:-https://api.nidaw.com/health}"

command -v kubectl >/dev/null 2>&1 || { echo 'kubectl is required' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo 'curl is required' >&2; exit 1; }

printf 'Validating release=%s namespace=%s\n' "$RELEASE" "$NAMESPACE"
curl --fail --silent --show-error "$API_HEALTH_URL" >/dev/null
curl --fail --silent --show-error "${API_HEALTH_URL%/health}/ready" >/dev/null
kubectl rollout status "deployment/${RELEASE}-backend" -n "$NAMESPACE" --timeout=300s
kubectl rollout status "deployment/${RELEASE}-frontend" -n "$NAMESPACE" --timeout=300s

# The backend image contains psql; credentials are read inside the pod from its
# injected environment rather than expanded in the operator's shell.
kubectl exec -n "$NAMESPACE" "deployment/${RELEASE}-backend" -- sh -c \
  'PGPASSWORD="$DB_PASSWORD" psql -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1"' >/dev/null

cat <<'NOTICE'
API, readiness endpoint, backend/frontend rollouts, and database connectivity passed.
Kafka connectivity is not asserted by this script; use a separately approved broker-level probe.
NOTICE
