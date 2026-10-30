#!/usr/bin/env python3
"""Static regression checks for known Helm deployment contract invariants."""
from pathlib import Path
import re
import yaml

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "platform/helm/nidaw"


def load_values(name):
    return yaml.safe_load((CHART / name).read_text(encoding="utf-8"))


def quantity(value):
    """Convert common Kubernetes CPU/memory quantities to a comparable scalar."""
    text = str(value).strip()
    if text.endswith("m"):
        return float(text[:-1]) / 1000
    match = re.fullmatch(r"([0-9.]+)(Ki|Mi|Gi|Ti|K|M|G|T)?", text)
    assert match, f"Unsupported quantity in static test: {text}"
    amount = float(match.group(1))
    unit = match.group(2)
    factors = {None: 1, "Ki": 1024, "Mi": 1024**2, "Gi": 1024**3,
               "Ti": 1024**4, "K": 1000, "M": 1000**2,
               "G": 1000**3, "T": 1000**4}
    return amount * factors[unit]


for filename in ("values-dev.yaml", "values-staging.yaml", "values-prod.yaml"):
    values = load_values(filename)
    ingress = values.get("ingress", {})
    annotations = ingress.get("annotations", {}) or {}
    assert "nginx.ingress.kubernetes.io/rewrite-target" not in annotations, (
        f"{filename}: rewrite-target can rewrite all root-path requests and break API/SPA routes"
    )
    for component in ("backend", "frontend"):
        resources = values[component].get("resources", {})
        requests = resources.get("requests", {})
        limits = resources.get("limits", {})
        for resource in set(requests) & set(limits):
            assert quantity(requests[resource]) <= quantity(limits[resource]), (
                f"{filename}: {component} {resource} request exceeds limit"
            )

consumer_nginx = (ROOT / "apps/consumer_app/nginx.conf").read_text(encoding="utf-8")
driver_nginx = (ROOT / "apps/driver_app/nginx.conf").read_text(encoding="utf-8")
assert re.search(r"listen\s+8080\s*;", consumer_nginx)
assert re.search(r"listen\s+8080\s*;", driver_nginx)
for filename in ("values.yaml", "values-dev.yaml", "values-staging.yaml", "values-prod.yaml"):
    values = load_values(filename)
    assert values["frontend"]["service"]["targetPort"] == 8080, filename
    assert values["frontend"]["livenessProbe"]["httpGet"]["path"] == "/health", filename
    assert values["frontend"]["readinessProbe"]["httpGet"]["path"] == "/ready", filename

prod = load_values("values-prod.yaml")
assert quantity(prod["backend"]["resources"]["requests"]["memory"]) <= quantity(
    prod["backend"]["resources"]["limits"]["memory"]
)

# Workflows intentionally keep production deployment blocked pending migration review.
prod_workflow = (ROOT / ".github/workflows/deploy-prod.yml").read_text(encoding="utf-8")
assert "Fail closed until production migration execution is reviewed" in prod_workflow
assert "exit 1" in prod_workflow.split("Fail closed until production migration execution is reviewed", 1)[1].split("- name:", 1)[0]

print("PASS: all environment values preserve root API/SPA paths without global rewrite-target")
print("PASS: CPU and memory requests do not exceed limits for backend/frontend")
print("PASS: frontend Service targetPort matches the Nginx listen port (8080)")
print("PASS: frontend health/readiness probes target configured Nginx endpoints")
print("PASS: production migration-review fail-closed guard remains intact")
