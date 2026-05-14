#!/usr/bin/env bash
set -euo pipefail

AUTH_BASE="${AUTH_BASE:-http://127.0.0.1:30184}"
API_BASE="${API_BASE:-http://127.0.0.1:30181}"
DATA_BASE="${DATA_BASE:-http://127.0.0.1:30182}"
NAMESPACE="${NAMESPACE:-mubench-real}"
K6_SCRIPT="${K6_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/RealisticServices/k6/realistic-flow.js}"
K6_OUT="${K6_OUT:-/tmp/mubench-real-k6.jsonl}"

echo "[1/5] Health checks"
curl -fsS "${AUTH_BASE}/health" | python3 -m json.tool
curl -fsS "${API_BASE}/health" | python3 -m json.tool
curl -fsS "${DATA_BASE}/health" | python3 -m json.tool

echo "[2/5] Login y token"
TOKEN=$(curl -fsS -X POST "${AUTH_BASE}/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}' | \
  python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')

if [[ -z "${TOKEN}" ]]; then
  echo "No se pudo obtener token" >&2
  exit 1
fi

echo "[3/5] Lectura y escritura funcional"
curl -fsS "${API_BASE}/users?limit=5" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool

UNIQUE_USER="validator_$(date +%s)"
curl -fsS -X POST "${API_BASE}/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${UNIQUE_USER}\",\"email\":\"${UNIQUE_USER}@example.com\"}" | python3 -m json.tool

echo "[4/5] Conteo directo en Postgres"
kubectl exec -n "${NAMESPACE}" deploy/postgres -- \
  psql -U mubench -d mubench_real -t -c 'SELECT COUNT(*) AS total_users FROM app_users;' | tr -d ' '

echo "[5/5] Carga corta con k6"
AUTH_BASE="${AUTH_BASE}" API_BASE="${API_BASE}" K6_INSECURE_SKIP_TLS_VERIFY=true \
  k6 run --quiet --out json="${K6_OUT}" "${K6_SCRIPT}"

python3 - <<'PY'
import json
import os

path = os.environ.get('K6_OUT', '/tmp/mubench-real-k6.jsonl')
durations = []
failed = 0
total_failed_points = 0

with open(path) as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('type') != 'Point':
            continue
        metric = obj.get('metric')
        value = obj.get('data', {}).get('value', 0)
        if metric == 'http_req_duration':
            durations.append(float(value))
        elif metric == 'http_req_failed':
            total_failed_points += 1
            failed += int(value)

durations.sort()
avg = sum(durations) / len(durations) if durations else 0
p95 = durations[min(int(len(durations) * 0.95), len(durations) - 1)] if durations else 0
err = (failed / total_failed_points * 100) if total_failed_points else 0

print({'avg_ms': round(avg, 2), 'p95_ms': round(p95, 2), 'err_pct': round(err, 2), 'samples': len(durations)})
PY

echo "Validación completada para el escenario Postgres real."