#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/experiments/05-mubench-advanced/k8s-controls/15-s4-semantic-services.yaml"
NS="mubench-s4"

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
kubectl apply -f "$MANIFEST"

for dep in postgres-s4 auth-service-s4 data-service-s4 api-service-s4; do
  kubectl rollout status deployment/$dep -n "$NS" --timeout=240s
done

echo "S4 semantic-equivalent mode ready in $NS"
echo "auth: http://127.0.0.1:32184"
echo "api:  http://127.0.0.1:32181"
echo "data: http://127.0.0.1:32182"
