#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ING_FILE="$ROOT_DIR/ratelimit/ingress-rate-limit.yaml"

# Limpiar politicas de control 3 para no interferir
if [[ -f "$ROOT_DIR/../03-network-policies/policies/network-policies.yaml" ]]; then
  microk8s kubectl delete -f "$ROOT_DIR/../03-network-policies/policies/network-policies.yaml" --ignore-not-found >/dev/null 2>&1 || true
fi

microk8s kubectl apply -f "$ING_FILE"

echo "[ratelimit] Ingress con rate limiting aplicado"
