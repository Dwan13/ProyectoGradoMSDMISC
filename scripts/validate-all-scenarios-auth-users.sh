#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Testing/results/validation"
mkdir -p "$OUT_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
OUT_CSV="$OUT_DIR/validate-all-scenarios-auth-users_${TS}.csv"

echo "scenario,auth_base,api_base,login_ok,jwt_prefix,created_username,create_ok,list_contains_user" > "$OUT_CSV"

# scenario_name auth_port api_port
SCENARIOS=(
  "S1 30084 30081"
  "S2 30184 30181"
  "S3eq 31184 31181"
  "S4 32184 32181"
)

for entry in "${SCENARIOS[@]}"; do
  set -- $entry
  SC="$1"
  AUTH_PORT="$2"
  API_PORT="$3"

  AUTH_BASE="http://127.0.0.1:${AUTH_PORT}"
  API_BASE="http://127.0.0.1:${API_PORT}"

  LOGIN_JSON="$(curl --max-time 12 -s -X POST "${AUTH_BASE}/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"demo","password":"demo123"}' || true)"

  TOKEN="$(printf '%s' "$LOGIN_JSON" | python3 -c 'import sys,json
try:
  obj=json.load(sys.stdin)
  print(obj.get("access_token",""))
except Exception:
  print("")')"

  if [[ -z "$TOKEN" ]]; then
    echo "${SC},${AUTH_BASE},${API_BASE},false,,,false,false" >> "$OUT_CSV"
    echo "[${SC}] login FAIL"
    continue
  fi

  USERNAME="pm_${SC,,}_$(date +%s)_$RANDOM"
  EMAIL="${USERNAME}@example.com"

  CREATE_JSON="$(curl --max-time 15 -s -X POST "${API_BASE}/users" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${USERNAME}\",\"email\":\"${EMAIL}\"}" || true)"

  CREATE_OK="$(printf '%s' "$CREATE_JSON" | python3 -c 'import sys,json
try:
  obj=json.load(sys.stdin)
  ok = isinstance(obj,dict) and ("user" in obj or obj.get("username"))
  print("true" if ok else "false")
except Exception:
  print("false")')"

  LIST_JSON="$(curl --max-time 20 -s "${API_BASE}/users?limit=20000" \
    -H "Authorization: Bearer ${TOKEN}" || true)"

  LIST_OK="false"
  if printf '%s' "$LIST_JSON" | grep -q "$USERNAME"; then
    LIST_OK="true"
  fi

  JWT_PREFIX="${TOKEN:0:20}..."
  echo "${SC},${AUTH_BASE},${API_BASE},true,${JWT_PREFIX},${USERNAME},${CREATE_OK},${LIST_OK}" >> "$OUT_CSV"

  echo "[${SC}] login OK | user=${USERNAME} | create=${CREATE_OK} | in_list=${LIST_OK}"
done

echo "CSV: $OUT_CSV"
cat "$OUT_CSV"
