#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/experiments/05-mubench-advanced/k8s-controls/14-s3-semantic-services.yaml"
NS="mubench-advanced"

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
kubectl apply -f "$MANIFEST"

for dep in postgres-s3 auth-service-s3 data-service-s3 api-service-s3; do
  kubectl rollout status deployment/$dep -n "$NS" --timeout=240s
done

echo "S3 semantic-equivalent mode ready in $NS"
echo "auth: http://127.0.0.1:31184"
echo "api:  http://127.0.0.1:31181"
echo "data: http://127.0.0.1:31182"
