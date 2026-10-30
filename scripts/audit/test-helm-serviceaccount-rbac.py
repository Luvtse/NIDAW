#!/usr/bin/env python3
"""Ensure application workloads do not receive unnecessary Kubernetes Secret API permissions."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
template = ROOT / "platform/helm/nidaw/templates/serviceaccount.yaml"
source = template.read_text(encoding="utf-8")

# The template should render only a ServiceAccount, never a Role or RoleBinding.
assert not re.search(r"(?m)^kind:\s*(?:Role|ClusterRole|RoleBinding|ClusterRoleBinding)\s*$", source), source
assert "kind: ServiceAccount" in source
assert ".Values.serviceAccount.create" in source
assert "include \"nidaw.serviceAccountName\" ." in source
assert "include \"nidaw.labels\" ." in source

# All application Secret dependencies are pod-level references, not app API reads.
for name in ("backend-deployment.yaml", "migration-job.yaml"):
    path = ROOT / "platform/helm/nidaw/templates" / name
    text = path.read_text(encoding="utf-8")
    assert "secretKeyRef:" in text, f"Expected pod-level secretKeyRef in {name}"

print("PASS: Helm application ServiceAccount template grants no Kubernetes API RBAC")
print("PASS: Secret consumption remains through pod secretKeyRef references")
print("NOTE: CI deployment identity needs separate, narrowly scoped Secret get access; live RBAC is not verified here")
