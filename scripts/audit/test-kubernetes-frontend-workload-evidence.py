#!/usr/bin/env python3
"""Documentable static evidence checks for Kubernetes frontend workload reconciliation."""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
K8S = ROOT / "platform/kubernetes"
COMPOSE = ROOT / "platform/docker/compose"

def load_yaml(path):
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)

base = load_yaml(K8S / "base/kustomization.yaml")
base_resources = []
for item in base["resources"]:
    docs = list(yaml.safe_load_all((K8S / "base" / item).read_text(encoding="utf-8")))
    base_resources.extend(doc for doc in docs if doc)

deployments = [doc for doc in base_resources if doc.get("kind") == "Deployment"]
services = [doc for doc in base_resources if doc.get("kind") == "Service"]
assert any(doc["metadata"]["name"] == "nidaw-backend" for doc in deployments)
assert not any(doc["metadata"]["name"] == "nidaw-frontend" for doc in deployments)
assert any(doc["metadata"]["name"] == "nidaw-frontend" for doc in services)

dev_compose = load_yaml(COMPOSE / "dev.yaml")
frontend = dev_compose["services"]["frontend"]
assert frontend["build"]["context"] == "../../../apps/consumer_app"
assert frontend["build"]["dockerfile"] == "Dockerfile.dev"

consumer_dockerfile = ROOT / "apps/consumer_app/Dockerfile"
driver_dockerfile = ROOT / "apps/driver_app/Dockerfile"
admin_dockerfile = ROOT / "apps/admin_console/Dockerfile"
assert consumer_dockerfile.is_file()
assert driver_dockerfile.is_file()
assert not admin_dockerfile.exists()

consumer_source = consumer_dockerfile.read_text(encoding="utf-8")
assert "--dart-define=API_BASE_URL=" in consumer_source
assert "--dart-define=WS_BASE_URL=" in consumer_source

for env in ("dev", "staging", "production"):
    overlay_path = K8S / "overlays" / env / "kustomization.yaml"
    overlay = load_yaml(overlay_path)
    targets = {
        patch.get("target", {}).get("name")
        for patch in overlay.get("patches", [])
        if patch.get("target", {}).get("kind") == "Deployment"
    }
    assert "nidaw-frontend" in targets, (env, targets)
    assert any(item.get("name") == "nidaw-frontend" for item in overlay.get("replicas", []))
    for generator in overlay.get("configMapGenerator", []):
        for item in generator.get("files", []):
            source = item.split("=", 1)[-1]
            assert not (K8S / "overlays" / env / source).is_file(), (env, source)

staging = load_yaml(K8S / "overlays/staging/kustomization.yaml")
assert any(
    source == ".env.staging"
    for generator in staging.get("secretGenerator", [])
    for source in generator.get("envs", [])
)
assert not (K8S / "overlays/staging/.env.staging").exists()

print("PASS: development Compose frontend build source is apps/consumer_app")
print("PASS: consumer and driver have separate Dockerfiles; admin console has no Dockerfile")
print("PASS: Kubernetes base has a frontend Service but no frontend Deployment")
print("PASS: all overlays currently target the absent frontend Deployment")
print("PASS: overlay Nginx files and staging Secret input are missing")
print("NOTE: evidence does not authorize inventing a multi-client Deployment or Secret")
