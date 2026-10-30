#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COMPOSE=(docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml)

case "${1:---safe}" in
  --safe)
    echo "Stopping NIDAW development containers. Named volumes and data will be preserved."
    "${COMPOSE[@]}" down
    ;;
  --volumes)
    echo "WARNING: this deletes local database, Redis, Kafka, MinIO, and other Compose volume data."
    read -r -p 'Type DELETE NIDAW DATA to continue: ' confirmation
    [[ "$confirmation" == 'DELETE NIDAW DATA' ]] || { echo 'Cancelled; no changes made.'; exit 1; }
    "${COMPOSE[@]}" down --volumes --remove-orphans
    ;;
  --help|-h)
    echo 'Usage: scripts/teardown.sh [--safe|--volumes]'
    echo '  --safe     Stop containers and preserve volumes (default).'
    echo '  --volumes  Destructively remove Compose volumes after explicit confirmation.'
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo 'Usage: scripts/teardown.sh [--safe|--volumes]' >&2
    exit 2
    ;;
esac
