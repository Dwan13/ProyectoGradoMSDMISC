#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POL_FILE="$ROOT_DIR/policies/network-policies.yaml"

microk8s kubectl delete -f "$POL_FILE" --ignore-not-found

echo "[netpol] Politicas removidas"
