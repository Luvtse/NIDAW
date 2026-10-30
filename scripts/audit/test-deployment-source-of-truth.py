#!/usr/bin/env python3
"""Static regression for NIDAW's checked-in deployment source of truth."""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

staging = read(".github/workflows/deploy-staging.yml")
production = read(".github/workflows/deploy-prod.yml")
consumer_dockerfile = read("apps/consumer_app/Dockerfile")
helm_deployment = read("platform/helm/nidaw/templates/frontend-deployment.yaml")
helm_service = read("platform/helm/nidaw/templates/frontend-service.yaml")
staging_values = read("platform/helm/nidaw/values-staging.yaml")

assert "helm upgrade --install" in staging
assert "./platform/helm/nidaw" in staging
assert "--values ./platform/helm/nidaw/values-staging.yaml" in staging
assert "kubectl rollout status deployment/${{ env.HELM_RELEASE }}-frontend" in staging
assert "context: ./apps/consumer_app" in staging
assert "API_BASE_URL=https://api.staging.nidaw.com" in staging
assert "WS_BASE_URL=wss://api.staging.nidaw.com/ws" in staging
assert "ENVIRONMENT=staging" in staging

assert "context: ./apps/consumer_app" in production
assert "API_BASE_URL=https://api.nidaw.com" in production
assert "WS_BASE_URL=wss://api.nidaw.com/ws" in production
assert "ENVIRONMENT=production" in production
assert "Fail closed until production migration execution is reviewed" in production
assert "exit 1" in production.split("Fail closed until production migration execution is reviewed", 1)[1].split("- name:", 1)[0]

assert "--dart-define=API_BASE_URL=${API_BASE_URL}" in consumer_dockerfile
assert "--dart-define=WS_BASE_URL=${WS_BASE_URL}" in consumer_dockerfile
assert "kind: Deployment" in helm_deployment
assert "kind: Service" in helm_service
assert "frontend.enabled" in helm_deployment
assert "Flutter web API URLs are compiled into the image via --dart-define" in staging_values

# The Kustomize overlays are separate files and are not the staging workflow's deploy command.
assert "kustomize build" not in staging
assert "kubectl apply -k" not in staging

for rel in (
    ".github/workflows/deploy-staging.yml",
    ".github/workflows/deploy-prod.yml",
    "platform/helm/nidaw/Chart.yaml",
    "platform/helm/nidaw/values-staging.yaml",
    "platform/helm/nidaw/values-prod.yaml",
    "platform/kubernetes/base/kustomization.yaml",
    "platform/kubernetes/overlays/dev/kustomization.yaml",
    "platform/kubernetes/overlays/staging/kustomization.yaml",
    "platform/kubernetes/overlays/production/kustomization.yaml",
):
    path = ROOT / rel
    list(yaml.safe_load_all(path.read_text(encoding="utf-8")))

print("PASS: staging workflow builds consumer frontend with staging compile-time endpoints and deploys via Helm")
print("PASS: production workflow builds consumer frontend with production compile-time endpoints")
print("PASS: Helm chart contains a gated frontend Deployment and Service")
print("PASS: production migration review remains fail-closed")
print("PASS: Kustomize overlays are not silently treated as the staging workflow's active deploy path")
print("NOTE: static checks do not validate image builds, Helm rendering, or cluster runtime")
