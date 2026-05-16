#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_MANIFEST="$ROOT_DIR/RealisticServices/k8s/02-postgres-real.yaml"
SERVICES_MANIFEST="$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml"

kubectl apply -f "$POSTGRES_MANIFEST"
kubectl delete pod -n mubench-real -l app=postgres --wait=false >/dev/null 2>&1 || true
kubectl apply -f "$SERVICES_MANIFEST"

kubectl rollout status deployment/postgres -n mubench-real --timeout=180s
kubectl rollout status deployment/auth-service -n mubench-real --timeout=180s
kubectl rollout status deployment/data-service -n mubench-real --timeout=180s
kubectl rollout status deployment/api-service -n mubench-real --timeout=180s

TOKEN=$(curl -s -X POST http://127.0.0.1:30184/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}' | \
  python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')

if [[ -z "$TOKEN" ]]; then
  echo "No se pudo obtener token del auth-service en mubench-real" >&2
  exit 1
fi

curl -s http://127.0.0.1:30181/users?limit=1 \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo "mubench-real listo en puertos 30181(api), 30182(data), 30184(auth)"
