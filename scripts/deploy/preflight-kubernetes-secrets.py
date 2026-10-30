#!/usr/bin/env python3
"""Validate required Kubernetes Secret metadata/keys without printing values."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from typing import Any

BACKEND_REQUIRED_KEYS = ("db-password", "jwt-secret", "kafka-brokers", "redis-url")
TLS_REQUIRED_KEYS = ("tls.crt", "tls.key")
DNS_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")


def valid_namespace_name(value: str) -> bool:
    return len(value) <= 63 and bool(DNS_LABEL.fullmatch(value))


def valid_secret_name(value: str) -> bool:
    if not value or len(value) > 253:
        return False
    return all(len(label) <= 63 and bool(DNS_LABEL.fullmatch(label)) for label in value.split("."))


def kubectl_json(args: list[str], description: str) -> dict[str, Any]:
    try:
        result = subprocess.run(
            ["kubectl", *args, "-o", "json"],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except FileNotFoundError:
        print("ERROR: kubectl is not installed or not on PATH.", file=sys.stderr)
        raise SystemExit(2)
    except subprocess.TimeoutExpired:
        print(f"ERROR: timed out checking {description}.", file=sys.stderr)
        raise SystemExit(2)

    if result.returncode != 0:
        # Deliberately do not echo kubectl stderr: avoid leaking cluster details.
        print(f"ERROR: unable to read {description}; check cluster access and resource existence.", file=sys.stderr)
        raise SystemExit(1)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"ERROR: kubectl returned invalid JSON for {description}.", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(value, dict):
        print(f"ERROR: unexpected response while checking {description}.", file=sys.stderr)
        raise SystemExit(2)
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--namespace", required=True, help="Target Kubernetes namespace")
    parser.add_argument("--backend-secret", default="nidaw-backend-secrets")
    parser.add_argument("--tls-secret", help="Optional TLS Secret to validate (e.g. nidaw-tls)")
    args = parser.parse_args()

    # Validate resource identifiers before invoking kubectl. This rejects
    # malformed names and prevents user input from being treated as CLI flags.
    if not valid_namespace_name(args.namespace):
        print("ERROR: namespace must be a valid DNS-label Kubernetes namespace name.", file=sys.stderr)
        return 2
    if not valid_secret_name(args.backend_secret):
        print("ERROR: backend Secret name must be a valid Kubernetes DNS-subdomain name.", file=sys.stderr)
        return 2
    if args.tls_secret and not valid_secret_name(args.tls_secret):
        print("ERROR: TLS Secret name must be a valid Kubernetes DNS-subdomain name.", file=sys.stderr)
        return 2

    # Do not query the cluster-scoped Namespace resource. A namespaced Secret
    # read is sufficient to prove that the target namespace exists and that the
    # deployment identity can access the required dependency. This avoids
    # requiring cluster-scoped `get namespaces` permission in CI.
    backend = kubectl_json(
        ["get", "secret", args.backend_secret, "--namespace", args.namespace],
        f"backend Secret {args.backend_secret} in namespace {args.namespace}",
    )
    if backend.get("metadata", {}).get("name") != args.backend_secret:
        print(f"ERROR: backend Secret {args.backend_secret} response did not match the requested name.", file=sys.stderr)
        return 1
    if backend.get("type") != "Opaque":
        print(f"ERROR: backend Secret {args.backend_secret} must have type Opaque.", file=sys.stderr)
        return 1
    data = backend.get("data")
    if not isinstance(data, dict):
        data = {}
    missing = [key for key in BACKEND_REQUIRED_KEYS if not isinstance(data.get(key), str) or not data[key]]
    if missing:
        print(f"ERROR: backend Secret {args.backend_secret} is missing required key(s): {', '.join(missing)}.", file=sys.stderr)
        return 1
    print(f"OK: backend Secret {args.backend_secret} exists and has all required keys (values not displayed).")

    if args.tls_secret:
        tls = kubectl_json(
            ["get", "secret", args.tls_secret, "--namespace", args.namespace],
            f"TLS Secret {args.tls_secret} in namespace {args.namespace}",
        )
        if tls.get("metadata", {}).get("name") != args.tls_secret:
            print(f"ERROR: TLS Secret {args.tls_secret} response did not match the requested name.", file=sys.stderr)
            return 1
        if tls.get("type") != "kubernetes.io/tls":
            print(f"ERROR: TLS Secret {args.tls_secret} must have type kubernetes.io/tls.", file=sys.stderr)
            return 1
        tls_data = tls.get("data")
        if not isinstance(tls_data, dict):
            tls_data = {}
        tls_missing = [key for key in TLS_REQUIRED_KEYS if not isinstance(tls_data.get(key), str) or not tls_data[key]]
        if tls_missing:
            print(f"ERROR: TLS Secret {args.tls_secret} is missing required key(s): {', '.join(tls_missing)}.", file=sys.stderr)
            return 1
        print(f"OK: TLS Secret {args.tls_secret} exists with certificate and private-key keys (values not displayed).")

    print(f"PASS: deployment Secret preflight succeeded for namespace {args.namespace}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
