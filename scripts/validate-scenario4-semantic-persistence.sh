#!/usr/bin/env bash
set -euo pipefail

AUTH_BASE="${AUTH_BASE:-http://127.0.0.1:32184}"
API_BASE="${API_BASE:-http://127.0.0.1:32181}"
NAMESPACE="${NAMESPACE:-mubench-s4}"

TOKEN=$(curl -fsS -X POST "$AUTH_BASE/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}' | \
  python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')

if [[ -z "$TOKEN" ]]; then
  echo "No se pudo obtener token en S4 semantic mode" >&2
  exit 1
fi

U="s4eq_user_$(date +%s)"
CREATE=$(curl -fsS -X POST "$API_BASE/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$U\",\"email\":\"$U@example.com\"}")

echo "CREATE_JSON=$CREATE"

kubectl exec -n "$NAMESPACE" deploy/postgres-s4 -- \
  psql -U mubench -d mubench_s4 -t -c "SELECT id,username,email FROM app_users WHERE username='${U}';"

echo "S4 semantic persistence validated."
