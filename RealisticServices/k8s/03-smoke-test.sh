#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:30081}"
AUTH_BASE="${AUTH_BASE:-http://127.0.0.1:18082}"

# Optional: you can port-forward auth-service to 18082 when NodePort is not exposed.
LOGIN_RESP=$(curl -s -X POST "${AUTH_BASE}/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","password":"demo123"}')

TOKEN=$(printf "%s" "${LOGIN_RESP}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')

if [[ -z "${TOKEN}" ]]; then
  echo "Login response inválida o sin token: ${LOGIN_RESP}"
  exit 1
fi

echo "Token obtenido (primeros 20 chars): ${TOKEN:0:20}..."

echo "Consultando /profile en api-service..."
curl -s "${API_BASE}/profile?user_id=1" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
