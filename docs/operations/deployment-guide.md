# Deployment Guide

This guide covers the complete deployment process for NIDAW across all environments (development, staging, production).

## 🎯 Overview

NIDAW uses a **GitOps-based deployment pipeline** with automated testing, blue-green deployments, and multi-region failover capabilities.

## 🌍 Environments

| Environment | Purpose | URL | Auto-Deploy |
|-------------|---------|-----|-------------|
| **Development** | Local development | localhost | N/A |
| **Staging** | Pre-production testing | staging.nidaw.com | On PR merge to `develop` |
| **Production** | Live user traffic | nidaw.com | On release tag |

## 📋 Prerequisites

### Required Tools

```bash
# Install required tools
brew install terraform kubectl helm awscli

# Or via apt (Ubuntu/Debian)
sudo apt-get install -y terraform kubectl helm awscli

# Verify installations
terraform --version  # >= 1.5.0
kubectl version --client  # >= 1.28.0
helm version  # >= 3.12.0
aws --version  # >= 2.13.0

AWS Configuration

# Configure AWS credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

Kubernetes Context

# Update kubeconfig
aws eks update-kubeconfig --name nidaw-production --region us-east-1

# Verify connection
kubectl get nodes

🚀 Deployment Process
1. Infrastructure Deployment (Terraform)
Staging Environment

cd infrastructure/environments/staging

# Initialize Terraform
terraform init

# Plan changes
terraform plan -out=plan.tfplan

# Review plan
terraform show plan.tfplan

# Apply changes
terraform apply plan.tfplan

Production Environment

cd infrastructure/environments/production

# Initialize Terraform
terraform init

# Plan changes
terraform plan -out=plan.tfplan

# Review plan (CRITICAL - review thoroughly)
terraform show plan.tfplan

# Apply changes
terraform apply plan.tfplan

2. Application Deployment (Helm)
Build Docker Images

# Backend (repository-root context includes the migration assets)
VERSION="$(git rev-parse --short HEAD)"
docker build -f services/api/Dockerfile -t ghcr.io/ORG/REPO/backend:"${VERSION}" .

# Consumer web app (URLs are compiled into the Flutter web build)
docker build -f apps/consumer_app/Dockerfile \
  --build-arg API_BASE_URL=https://api.staging.nidaw.com \
  --build-arg WS_BASE_URL=wss://api.staging.nidaw.com/ws \
  --build-arg ENVIRONMENT=staging \
  -t ghcr.io/ORG/REPO/frontend:"${VERSION}" apps/consumer_app

# Replace ORG/REPO with the actual GitHub repository and push only after review.

Deployment status and safety

The production release workflow is intentionally blocked at validation while the driver workload and production SQL migration ordering/rollback contract remain unapproved. Do not use an ad-hoc `helm upgrade` to bypass that guard.

For a reviewed staging release, build images using the repository's current Dockerfiles and use the `backend.image.*` / `frontend.image.*` chart keys (not the obsolete `image.backend.*` keys). The staging workflow is the supported staging entry point and requires `STAGING_DB_HOST` plus the `nidaw-backend-secrets` Kubernetes Secret with `db-password`, `jwt-secret`, `kafka-brokers`, and `redis-url` keys.

The staging chart enables a Helm `pre-install` / `pre-upgrade` migration Job. It runs the versioned migration script from the new backend image before the workload rollout; if a migration fails, Helm stops the upgrade. The runner skips development seed data outside development/staging/test/CI and skips the T5 fault-injection table outside test/CI.

Production migration execution remains disabled until migration ordering, backward compatibility, and rollback have been reviewed. Do not bypass the release workflow's fail-closed guard.

Verify staging migrations:

```bash
kubectl exec -n nidaw-staging deploy/nidaw-staging-backend -- sh -c \
  'PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version, name, applied_at FROM schema_migrations ORDER BY version"'
```

4. Kafka Topic Creation

# Create required topics
kubectl exec -n production statefulset/kafka -- \
  kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic nidus.rides \
  --partitions 6 \
  --replication-factor 3 \
  --if-not-exists

kubectl exec -n production statefulset/kafka -- \
  kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic nidus.locations \
  --partitions 12 \
  --replication-factor 3 \
  --if-not-exists

# Repeat for other topics...

🔄 Deployment Strategies
Blue-Green Deployment

# Deploy to Green environment
helm upgrade --install nidaw-green ./platform/helm/nidaw \
  --namespace production \
  --set deployment.color=green \
  --wait

# Run smoke tests against Green
./scripts/smoke-test.sh https://green.api.nidaw.com

# Switch traffic to Green
kubectl patch ingress nidaw-ingress -n production -p \
  '{"spec":{"rules":[{"host":"api.nidaw.com","http":{"paths":[{"path":"/","backend":{"serviceName":"nidaw-green","servicePort":80}}]}}]}}'

# Monitor for 15 minutes
kubectl logs -f -n production deployment/nidaw-green

# Terminate Blue environment
helm uninstall nidaw-blue -n production

Canary Deployment

# Deploy canary (10% traffic)
helm upgrade --install nidaw-canary ./platform/helm/nidaw \
  --namespace production \
  --set deployment.strategy=canary \
  --set deployment.canaryWeight=10 \
  --wait

# Monitor metrics
kubectl top pods -n production -l app=nidaw-canary

# Gradually increase traffic
helm upgrade nidaw-canary ./platform/helm/nidaw \
  --set deployment.canaryWeight=25 \
  --wait

# Continue until 100%
helm upgrade nidaw-canary ./platform/helm/nidaw \
  --set deployment.canaryWeight=100 \
  --wait

📊 Post-Deployment Verification
Health Checks

# Check pod status
kubectl get pods -n production

# Check deployment status
kubectl get deployments -n production

# Check services
kubectl get services -n production

# Check ingress
kubectl get ingress -n production

Smoke Tests

# Run automated smoke tests
./scripts/smoke-test.sh https://api.nidaw.com

# Manual verification
curl https://api.nidaw.com/health
curl https://api.nidaw.com/ready

# Test critical endpoints
curl -X POST https://api.nidaw.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@nidaw.com","password":"test123"}'

Monitoring

# Open Grafana
open https://grafana.nidaw.com

# Check Prometheus targets
open https://prometheus.nidaw.com/targets

# View Jaeger traces
open https://jaeger.nidaw.com

🔙 Rollback Procedures
Immediate Rollback

# Rollback to previous release
helm rollback nidaw-production 1

# Or rollback to specific version
helm rollback nidaw-production --revision 5

Manual Rollback

# Identify previous version
helm history nidaw-production

# Rollback
helm rollback nidaw-production <REVISION>

# Verify rollback
kubectl get pods -n production

📝 Deployment Checklist
Pre-Deployment
All tests passing in CI
Security scan clean
Terraform plan reviewed
Database migrations tested
Rollback plan documented
Stakeholders notified
Monitoring dashboards ready
On-call engineer assigned
During Deployment
Terraform apply successful
Helm upgrade successful
Database migrations complete
Kafka topics created
Pods running and healthy
Smoke tests passing
No error spikes in logs
Latency within normal range
Post-Deployment
Business metrics stable
User feedback monitored
Documentation updated
Deployment announced
Rollback window closed (1 hour)
Post-deployment review scheduled
🛠️ Automation
GitHub Actions Workflow

# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Deploy Infrastructure
        run: |
          cd infrastructure/environments/production
          terraform init
          terraform apply -auto-approve
      
      - name: Build and Push Images
        run: |
          docker build -t nidaw/backend:${{ github.ref_name }} ./services/api
          docker push nidaw/backend:${{ github.ref_name }}
      
      - name: Deploy Application
        run: |
          helm upgrade --install nidaw-production ./platform/helm/nidaw \
            --namespace production \
            --set backend.image.tag=${{ github.ref_name }} \
            --wait
      
      - name: Verify Deployment
        run: ./scripts/smoke-test.sh https://api.nidaw.com

📞 Support
Deployment Issues
Slack: #deployment-support
Email: platform@nidaw.com
PagerDuty: Production Deployment

Emergency Contacts

Role		Name	Phone	Email
Platform Lead	[Name]	-654	platform@nidaw.com
SRE Lead	[Name]	-655	sre@nidaw.com
CTO		[Name]	-656	cto@nidaw.com

Last Updated: July 2026
Owner: Platform Engineering Team
Review Cadence: Monthly
