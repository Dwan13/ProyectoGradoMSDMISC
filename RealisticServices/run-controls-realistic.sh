#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${ROOT_DIR}/results/controls"
mkdir -p "${RESULTS_DIR}"

wait_http() {
  local url="$1"
  local max_wait="${2:-40}"
  local i
  for ((i = 1; i <= max_wait; i++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_one() {
  local control="$1"
  local auth_base="$2"
  local api_base="$3"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  local out_json="${RESULTS_DIR}/${control}-${stamp}.json"

  echo "[INFO] Running ${control} AUTH_BASE=${auth_base} API_BASE=${api_base}"
  if k6 run \
    --no-thresholds \
    -e AUTH_BASE="${auth_base}" \
    -e API_BASE="${api_base}" \
    --out json="${out_json}" \
    "${ROOT_DIR}/k6/realistic-flow.js"; then
    echo "[INFO] Output: ${out_json}"
  else
    echo "[WARN] Scenario ${control} failed. Partial output (if any): ${out_json}"
  fi
}

# Baseline
"${ROOT_DIR}/controls/apply-control.sh" baseline
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/rs-auth-pf.log 2>&1 &
PF_AUTH=$!
microk8s kubectl port-forward -n realistic svc/api-service 30081:8080 >/tmp/rs-api-pf.log 2>&1 &
PF_API=$!
wait_http http://127.0.0.1:18082/health 45 || echo "[WARN] auth baseline endpoint not ready"
wait_http http://127.0.0.1:30081/health 45 || echo "[WARN] api baseline endpoint not ready"
run_one baseline http://127.0.0.1:18082 http://127.0.0.1:30081
kill "$PF_AUTH" "$PF_API" >/dev/null 2>&1 || true

# C1 API Gateway
"${ROOT_DIR}/controls/apply-control.sh" c1 || true
microk8s kubectl -n ingress port-forward service/ingress 32080:80 >/tmp/rs-ingress-pf.log 2>&1 &
PF_ING=$!
wait_http http://127.0.0.1:32080/auth/health 60 || echo "[WARN] ingress auth endpoint not ready"
wait_http http://127.0.0.1:32080/api/health 60 || echo "[WARN] ingress api endpoint not ready"
run_one c1-gateway http://127.0.0.1:32080/auth http://127.0.0.1:32080/api
kill "$PF_ING" >/dev/null 2>&1 || true

# C3 NetworkPolicy
"${ROOT_DIR}/controls/apply-control.sh" c3
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/rs-auth-pf.log 2>&1 &
PF_AUTH=$!
microk8s kubectl port-forward -n realistic svc/api-service 30081:8080 >/tmp/rs-api-pf.log 2>&1 &
PF_API=$!
wait_http http://127.0.0.1:18082/health 45 || echo "[WARN] auth c3 endpoint not ready"
wait_http http://127.0.0.1:30081/health 45 || echo "[WARN] api c3 endpoint not ready"
run_one c3-netpol http://127.0.0.1:18082 http://127.0.0.1:30081
kill "$PF_AUTH" "$PF_API" >/dev/null 2>&1 || true

# C4 Rate limit
"${ROOT_DIR}/controls/apply-control.sh" c4
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/rs-auth-pf.log 2>&1 &
PF_AUTH=$!
microk8s kubectl port-forward -n realistic svc/api-service 30081:8080 >/tmp/rs-api-pf.log 2>&1 &
PF_API=$!
wait_http http://127.0.0.1:18082/health 45 || echo "[WARN] auth c4 endpoint not ready"
wait_http http://127.0.0.1:30081/health 45 || echo "[WARN] api c4 endpoint not ready"
run_one c4-ratelimit http://127.0.0.1:18082 http://127.0.0.1:30081
kill "$PF_AUTH" "$PF_API" >/dev/null 2>&1 || true

# C2 mTLS optional
if "${ROOT_DIR}/controls/apply-control.sh" c2; then
  microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/rs-auth-pf.log 2>&1 &
  PF_AUTH=$!
  microk8s kubectl port-forward -n realistic svc/api-service 30081:8080 >/tmp/rs-api-pf.log 2>&1 &
  PF_API=$!
  wait_http http://127.0.0.1:18082/health 45 || echo "[WARN] auth c2 endpoint not ready"
  wait_http http://127.0.0.1:30081/health 45 || echo "[WARN] api c2 endpoint not ready"
  run_one c2-mtls http://127.0.0.1:18082 http://127.0.0.1:30081
  kill "$PF_AUTH" "$PF_API" >/dev/null 2>&1 || true
else
  echo "[WARN] C2 skipped (no service mesh found)."
fi

# back to baseline
"${ROOT_DIR}/controls/apply-control.sh" baseline

echo "[INFO] Done. Results in ${RESULTS_DIR}"
