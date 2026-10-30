#!/bin/bash
set -euo pipefail

echo "🚀 Setting up NIDAW local development environment..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "❌ Docker Compose v2 is required but not installed."; exit 1; }

# Copy env file if not exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp env.example .env
    echo "⚠️  Please update .env with your API keys before starting services."
fi

# Compose reads .env itself, but this shell also needs the credentials for MinIO setup.
set -a
# shellcheck disable=SC1091
source .env
set +a

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p platform/monitoring/grafana/dashboards
mkdir -p config/minio

# Start services
echo "🐳 Starting Docker containers..."
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
sleep 10

# Initialize MinIO buckets
echo "🪣 Initializing MinIO buckets..."
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T minio mc alias set local http://localhost:9000 "${MINIO_USER:?}" "${MINIO_PASSWORD:?}"
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T minio mc mb local/mlflow || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T minio mc mb local/events || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T minio mc mb local/backups || true

# Create Kafka topics
echo "📨 Creating Kafka topics..."
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T kafka kafka-topics --create --topic nidus.rides --bootstrap-server localhost:9092 --partitions 6 --replication-factor 1 || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T kafka kafka-topics --create --topic haven.bookings --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T kafka kafka-topics --create --topic vorax.orders --bootstrap-server localhost:9092 --partitions 6 --replication-factor 1 || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T kafka kafka-topics --create --topic payments --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml exec -T kafka kafka-topics --create --topic driver.locations --bootstrap-server localhost:9092 --partitions 12 --replication-factor 1 || true

# Seed database
echo "🌱 Seeding database with sample data..."
./scripts/seed/seed-data.sh

echo ""
echo "✅ NIDAW development environment is ready!"
echo ""
echo "📊 Service URLs:"
echo "  - Backend API:      http://localhost:8080"
echo "  - Swagger UI:       http://localhost:8084"
echo "  - Grafana:          http://localhost:3001 (admin/admin)"
echo "  - Prometheus:       http://localhost:9090"
echo "  - Jaeger:           http://localhost:16686"
echo "  - Kafka UI:         http://localhost:8083"
echo "  - Redis UI:         http://localhost:8081"
echo "  - MinIO Console:    http://localhost:9001 (see MINIO_USER/MINIO_PASSWORD in .env)"
echo "  - MLflow:           http://localhost:5000"
echo ""
echo "🔧 Useful commands:"
echo "  - View logs:        docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml logs -f backend"
echo "  - Stop services:    docker compose -f platform/docker/compose/base.yaml -f platform/docker/compose/dev.yaml down"
echo "  - Stop services:     ./scripts/teardown.sh --safe"
echo "  - Delete local data: ./scripts/teardown.sh --volumes (requires confirmation)"