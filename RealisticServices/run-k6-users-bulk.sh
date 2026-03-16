#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

NAMESPACE="${NAMESPACE:-realistic}"
AUTH_PORT="${AUTH_PORT:-18082}"
API_PORT="${API_PORT:-18081}"
APPLY_BASELINE="${APPLY_BASELINE:-1}"
PF_RETRIES="${PF_RETRIES:-4}"

AUTH_BASE="${AUTH_BASE:-http://127.0.0.1:${AUTH_PORT}}"
API_BASE="${API_BASE:-http://127.0.0.1:${API_PORT}}"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_JSON="${RESULTS_DIR}/k6-users-bulk-${STAMP}.json"

cleanup() {
  kill "${PF_AUTH:-}" "${PF_API:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_port_forward() {
  local service="$1"
  local base_port="$2"
  local log_file="$3"
  local pid_var="$4"
  local port_var="$5"

  local attempt
  for attempt in $(seq 1 "${PF_RETRIES}"); do
    local candidate_port=$((base_port + (attempt - 1) * 100))
    echo "[INFO] Starting port-forward ${service} -> ${candidate_port} (attempt ${attempt}/${PF_RETRIES})"
    microk8s kubectl -n "${NAMESPACE}" port-forward "svc/${service}" "${candidate_port}:8080" >"${log_file}" 2>&1 &
    local pf_pid=$!
    sleep 2

    if ps -p "${pf_pid}" >/dev/null 2>&1; then
      printf -v "${pid_var}" '%s' "${pf_pid}"
      printf -v "${port_var}" '%s' "${candidate_port}"
      return 0
    fi

    kill "${pf_pid}" >/dev/null 2>&1 || true
  done

  return 1
}

if [[ "${APPLY_BASELINE}" == "1" ]] && [[ -x "${ROOT_DIR}/controls/apply-control.sh" ]]; then
  echo "[INFO] Applying baseline control set"
  "${ROOT_DIR}/controls/apply-control.sh" baseline || true
fi

if ! start_port_forward "auth-service" "${AUTH_PORT}" "/tmp/rs-auth-bulk-pf.log" PF_AUTH AUTH_PORT_ACTUAL; then
  echo "[ERROR] auth-service port-forward failed"
  tail -n 20 /tmp/rs-auth-bulk-pf.log || true
  exit 1
fi
if ! start_port_forward "api-service" "${API_PORT}" "/tmp/rs-api-bulk-pf.log" PF_API API_PORT_ACTUAL; then
  echo "[ERROR] api-service port-forward failed"
  tail -n 20 /tmp/rs-api-bulk-pf.log || true
  exit 1
fi

AUTH_BASE="http://127.0.0.1:${AUTH_PORT_ACTUAL}"
API_BASE="http://127.0.0.1:${API_PORT_ACTUAL}"

echo "[INFO] AUTH_BASE=${AUTH_BASE}"
echo "[INFO] API_BASE=${API_BASE}"
echo "[INFO] Output=${OUT_JSON}"

auth_health="$(curl -s -o /dev/null -w '%{http_code}' "${AUTH_BASE}/health" || true)"
api_health="$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE}/health" || true)"
if [[ "${auth_health}" != "200" || "${api_health}" != "200" ]]; then
  echo "[ERROR] health check failed (auth=${auth_health}, api=${api_health})"
  exit 1
fi

k6 run \
  -e AUTH_BASE="${AUTH_BASE}" \
  -e API_BASE="${API_BASE}" \
  -e CREATE_VUS="${CREATE_VUS:-15}" \
  -e CREATE_DURATION="${CREATE_DURATION:-45s}" \
  -e LIST_START="${LIST_START:-50s}" \
  -e LIST_VUS="${LIST_VUS:-5}" \
  -e LIST_DURATION="${LIST_DURATION:-25s}" \
  -e LIST_LIMIT="${LIST_LIMIT:-100}" \
  --out json="${OUT_JSON}" \
  "${ROOT_DIR}/k6/users-bulk-create-list.js"

echo "[INFO] k6 finished: ${OUT_JSON}"
