#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ING_FILE="$ROOT_DIR/ratelimit/ingress-rate-limit.yaml"

microk8s kubectl delete -f "$ING_FILE" --ignore-not-found

echo "[ratelimit] Ingress de rate limiting removido"
