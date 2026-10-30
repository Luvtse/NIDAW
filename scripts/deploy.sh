#!/usr/bin/env bash
set -euo pipefail

# Deliberately fail closed: the chart still lacks a driver workload and the
# production SQL migration ordering/rollback contract has not been reviewed.
# Do not mutate production infrastructure or a cluster until those contracts
# are completed and reviewed.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:-production}"
TF_DIR="${ROOT_DIR}/infrastructure/environments/${ENVIRONMENT}"
CHART_DIR="${ROOT_DIR}/platform/helm/nidaw"

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh [--check | --plan-infrastructure]

Safe modes:
  --check                 Verify local deployment inputs without changing resources.
  --plan-infrastructure   Reserved for a reviewed rollout; currently refused
                          while the application deployment contract is incomplete.

This script intentionally does not deploy applications yet. The chart is missing
the driver workload and production migration safety is not approved. No apply,
image push, database migration, or Kubernetes mutation is performed here.
USAGE
}

mode="${1:---check}"
case "${mode}" in
  --help|-h) usage; exit 0 ;;
  --check|--plan-infrastructure) ;;
  *) echo "Unsupported option: ${mode}" >&2; usage >&2; exit 2 ;;
esac

[[ -d "${TF_DIR}" ]] || { echo "Terraform environment not found: ${TF_DIR}" >&2; exit 1; }
[[ -f "${TF_DIR}/main.tf" ]] || { echo "Terraform main.tf missing: ${TF_DIR}" >&2; exit 1; }
[[ -f "${CHART_DIR}/Chart.yaml" ]] || { echo "Helm chart not found: ${CHART_DIR}" >&2; exit 1; }

missing=()
[[ -f "${ROOT_DIR}/services/api/Dockerfile" ]] || missing+=("services/api/Dockerfile")
[[ -f "${ROOT_DIR}/apps/consumer_app/Dockerfile" ]] || missing+=("apps/consumer_app/Dockerfile")
[[ -f "${ROOT_DIR}/apps/driver_app/Dockerfile" ]] || missing+=("apps/driver_app/Dockerfile")

printf 'Deployment preflight: environment=%s\n' "${ENVIRONMENT}"
printf 'Terraform: %s\nHelm chart: %s\n' "${TF_DIR}" "${CHART_DIR}"
printf '\nBLOCKED: production deployment contract is incomplete:\n' >&2
if ((${#missing[@]})); then printf ' - %s\n' "${missing[@]}" >&2; fi
printf ' - Helm chart does not define a driver workload.\n' >&2
printf ' - SQL migration ordering, backward compatibility, and rollback are not approved for production.\n' >&2
printf '\nNo infrastructure or application changes were made.\n' >&2
if [[ "${mode}" == "--plan-infrastructure" ]]; then
  echo "Refusing to plan a partial production rollout until deployment blockers are resolved." >&2
fi
exit 3

