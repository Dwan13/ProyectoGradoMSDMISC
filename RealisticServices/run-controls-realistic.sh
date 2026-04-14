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

start_pf() {
  local cmd="$1"
  local log_file="$2"
  local url_probe="$3"
  local max_wait="${4:-60}"
  local pid=""
  local attempt

  for attempt in 1 2 3; do
    eval "$cmd" >"${log_file}" 2>&1 &
    pid=$!
    sleep 2
    if ps -p "$pid" >/dev/null 2>&1 && wait_http "$url_probe" "$max_wait"; then
      echo "$pid"
      return 0
    fi
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    sleep 1
  done

  return 1
}

cleanup_pf_port() {
  local local_port="$1"
  pkill -f "port-forward.*${local_port}:" >/dev/null 2>&1 || true
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
cleanup_pf_port 18082
cleanup_pf_port 30081
PF_AUTH=$(start_pf "microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080" /tmp/rs-auth-pf.log http://127.0.0.1:18082/health 45) || true
PF_API=$(start_pf "microk8s kubectl port-forward -n realistic svc/api-service 30081:8080" /tmp/rs-api-pf.log http://127.0.0.1:30081/health 45) || true
if [[ -n "${PF_AUTH:-}" && -n "${PF_API:-}" ]]; then
  run_one baseline http://127.0.0.1:18082 http://127.0.0.1:30081
else
  echo "[WARN] Baseline skipped: endpoints no listos"
fi
kill "${PF_AUTH:-}" "${PF_API:-}" >/dev/null 2>&1 || true

# C1 API Gateway
"${ROOT_DIR}/controls/apply-control.sh" c1 || true
cleanup_pf_port 32080
INGRESS_SVC="ingress"
if ! microk8s kubectl -n ingress get svc "${INGRESS_SVC}" >/dev/null 2>&1; then
  INGRESS_SVC="nginx-ingress-microk8s-controller"
fi
PF_ING=$(start_pf "microk8s kubectl -n ingress port-forward service/${INGRESS_SVC} 32080:80" /tmp/rs-ingress-pf.log http://127.0.0.1:32080/auth/health 70) || true
if [[ -n "${PF_ING:-}" ]] && wait_http http://127.0.0.1:32080/api/health 30; then
  run_one c1-gateway http://127.0.0.1:32080/auth http://127.0.0.1:32080/api
else
  echo "[WARN] C1 skipped: ingress no disponible en 32080"
fi
kill "${PF_ING:-}" >/dev/null 2>&1 || true

# C3 NetworkPolicy
"${ROOT_DIR}/controls/apply-control.sh" c3
cleanup_pf_port 18082
cleanup_pf_port 30081
PF_AUTH=$(start_pf "microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080" /tmp/rs-auth-pf.log http://127.0.0.1:18082/health 45) || true
PF_API=$(start_pf "microk8s kubectl port-forward -n realistic svc/api-service 30081:8080" /tmp/rs-api-pf.log http://127.0.0.1:30081/health 45) || true
if [[ -n "${PF_AUTH:-}" && -n "${PF_API:-}" ]]; then
  run_one c3-netpol http://127.0.0.1:18082 http://127.0.0.1:30081
else
  echo "[WARN] C3 skipped: endpoints no listos"
fi
kill "${PF_AUTH:-}" "${PF_API:-}" >/dev/null 2>&1 || true

# C4 Rate limit
"${ROOT_DIR}/controls/apply-control.sh" c4
cleanup_pf_port 18082
cleanup_pf_port 30081
PF_AUTH=$(start_pf "microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080" /tmp/rs-auth-pf.log http://127.0.0.1:18082/health 45) || true
PF_API=$(start_pf "microk8s kubectl port-forward -n realistic svc/api-service 30081:8080" /tmp/rs-api-pf.log http://127.0.0.1:30081/health 45) || true
if [[ -n "${PF_AUTH:-}" && -n "${PF_API:-}" ]]; then
  run_one c4-ratelimit http://127.0.0.1:18082 http://127.0.0.1:30081
else
  echo "[WARN] C4 skipped: endpoints no listos"
fi
kill "${PF_AUTH:-}" "${PF_API:-}" >/dev/null 2>&1 || true

# C2 mTLS optional
if "${ROOT_DIR}/controls/apply-control.sh" c2; then
  cleanup_pf_port 18082
  cleanup_pf_port 30081
  PF_AUTH=$(start_pf "microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080" /tmp/rs-auth-pf.log http://127.0.0.1:18082/health 45) || true
  PF_API=$(start_pf "microk8s kubectl port-forward -n realistic svc/api-service 30081:8080" /tmp/rs-api-pf.log http://127.0.0.1:30081/health 45) || true
  if [[ -n "${PF_AUTH:-}" && -n "${PF_API:-}" ]]; then
    run_one c2-mtls http://127.0.0.1:18082 http://127.0.0.1:30081
  else
    echo "[WARN] C2 skipped: endpoints no listos"
  fi
  kill "${PF_AUTH:-}" "${PF_API:-}" >/dev/null 2>&1 || true
else
  echo "[WARN] C2 skipped (no service mesh found)."
fi

# back to baseline
"${ROOT_DIR}/controls/apply-control.sh" baseline

echo "[INFO] Done. Results in ${RESULTS_DIR}"
