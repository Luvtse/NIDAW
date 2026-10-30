#!/usr/bin/env python3
"""Static regression checks for Kubernetes base wiring and overlay completeness."""
from pathlib import Path
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]
K8S = ROOT / "platform/kubernetes"

def load(path):
    with path.open(encoding="utf-8") as f:
        return list(yaml.safe_load_all(f))

base_kustomization = yaml.safe_load((K8S / "base/kustomization.yaml").read_text())
assert base_kustomization["kind"] == "Kustomization"
base_resources = set(base_kustomization["resources"])
assert base_resources == {"namespace.yaml", "backend-deployment.yaml", "backend-service.yaml", "frontend-service.yaml", "ingress.yaml"}

backend_deploy = next(x for x in load(K8S / "base/backend-deployment.yaml") if x and x.get("kind") == "Deployment")
backend_service = next(x for x in load(K8S / "base/backend-service.yaml") if x and x and x.get("kind") == "Service")
labels = backend_deploy["spec"]["template"]["metadata"]["labels"]
selector = backend_service["spec"]["selector"]
assert all(labels.get(k) == v for k, v in selector.items()), (labels, selector)
ports = backend_service["spec"]["ports"]
assert any(p["port"] == 80 and p["targetPort"] == 8080 for p in ports)
assert any(p["port"] == 8080 and p["targetPort"] == 8080 for p in ports)

# Namespace resources receive namePrefix, while the namespace transformer
# assigns workload namespace fields. Keep those names aligned and use a stable
# namespace label for intra-environment NetworkPolicy selectors.
base_namespace_docs = load(K8S / "base/namespace.yaml")
namespace_doc = next(x for x in base_namespace_docs if x and x.get("kind") == "Namespace")
assert namespace_doc["metadata"]["name"] == "nidaw"
assert namespace_doc["metadata"]["labels"].get("app.kubernetes.io/part-of") == "nidaw-platform"
for env, prefix, expected_namespace in (("dev", "dev-", "dev-nidaw"), ("staging", "staging-", "staging-nidaw"), ("production", "prod-", "prod-nidaw")):
    overlay = yaml.safe_load((K8S / "overlays" / env / "kustomization.yaml").read_text())
    assert overlay.get("namePrefix") == prefix, (env, overlay.get("namePrefix"))
    assert overlay.get("namespace") == expected_namespace, (env, overlay.get("namespace"))
network_policies = [x for x in base_namespace_docs if x and x.get("kind") == "NetworkPolicy"]
assert network_policies, "Expected base NetworkPolicy resources"
for policy in network_policies:
    selector_doc = policy.get("spec", {})
    for rule_group in (selector_doc.get("ingress", []), selector_doc.get("egress", [])):
        for rule in rule_group:
            for peer in rule.get("from", []) + rule.get("to", []):
                ns_selector = peer.get("namespaceSelector", {})
                labels = ns_selector.get("matchLabels", {})
                if "app.kubernetes.io/part-of" in labels:
                    assert labels["app.kubernetes.io/part-of"] == "nidaw-platform"
assert all(
    peer.get("namespaceSelector", {}).get("matchLabels", {}).get("kubernetes.io/metadata.name") != "nidaw"
    for policy in network_policies
    for group in (policy.get("spec", {}).get("ingress", []), policy.get("spec", {}).get("egress", []))
    for rule in group
    for peer in rule.get("from", []) + rule.get("to", [])
), "Environment-specific namespace names must not be hard-coded in base policy selectors"

# Record known blockers instead of hiding them behind a false "render passed" claim.
blockers = []
for env in ("dev", "staging", "production"):
    root = K8S / "overlays" / env
    doc = yaml.safe_load((root / "kustomization.yaml").read_text())
    if not (K8S / "base/kustomization.yaml").exists():
        blockers.append(f"{env}: base kustomization missing")
    for generator in doc.get("configMapGenerator", []):
        for entry in generator.get("files", []):
            source = entry.split("=", 1)[-1]
            if not (root / source).is_file():
                blockers.append(f"{env}: configMapGenerator file missing: {source}")
    for generator in doc.get("secretGenerator", []):
        for source in generator.get("envs", []):
            if not (root / source).is_file():
                blockers.append(f"{env}: secretGenerator env file missing: {source}")
    names = {x["metadata"]["name"] for filename in base_resources for x in load(K8S / "base" / filename) if x and x.get("kind") == "Deployment"}
    for patch in doc.get("patches", []):
        target = patch.get("target", {})
        if target.get("kind") == "Deployment" and target.get("name") not in names:
            blockers.append(f"{env}: patch target Deployment missing from base: {target.get('name')}")
    for replica in doc.get("replicas", []):
        if replica.get("name") not in names:
            blockers.append(f"{env}: replica target missing from base: {replica.get('name')}")

expected = {
    "dev: configMapGenerator file missing: nginx-dev.conf",
    "staging: configMapGenerator file missing: nginx-staging.conf",
    "staging: secretGenerator env file missing: .env.staging",
    "production: configMapGenerator file missing: nginx-prod.conf",
}
assert expected.issubset(set(blockers)), f"Expected overlay blockers not detected: {blockers}"
assert any("Deployment missing from base: nidaw-frontend" in b for b in blockers), blockers
print("PASS: Kubernetes base resources, backend selector and Kong/Ingress ports are consistent")
print("PASS: overlay audit detects known non-renderable references and missing frontend Deployment")
print("Known blockers:")
for item in blockers:
    print(f" - {item}")
