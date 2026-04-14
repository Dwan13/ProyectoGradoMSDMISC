#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="realistic"
OUTPUT_DIR="${ROOT_DIR}/RealisticServices/results"
AUTH_PORT="18082"
API_PORT="30081"
INJECT_DELAY="15"
RECOVERY_TIMEOUT="180"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --namespace <ns>         Namespace realistic (default: realistic)
  --output-dir <path>      Directorio de salida (default: RealisticServices/results)
  --auth-port <port>       Puerto local auth-service (default: 18082)
  --api-port <port>        Puerto local api-service (default: 30081)
  --inject-delay <sec>     Segundos antes de inyectar fallo (default: 15)
  --recovery-timeout <sec> Maximo de espera de recuperacion (default: 180)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NS="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --auth-port)
      AUTH_PORT="$2"
      shift 2
      ;;
    --api-port)
      API_PORT="$2"
      shift 2
      ;;
    --inject-delay)
      INJECT_DELAY="$2"
      shift 2
      ;;
    --recovery-timeout)
      RECOVERY_TIMEOUT="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Opcion desconocida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_CSV="${OUTPUT_DIR}/fault-tolerance-${STAMP}.csv"
OUT_MD="${OUTPUT_DIR}/fault-tolerance-${STAMP}.md"
TMP_DIR="$(mktemp -d /tmp/mubench-fault.XXXXXX)"
trap 'rm -rf "$TMP_DIR"; kill ${PF_AUTH:-0} ${PF_API:-0} >/dev/null 2>&1 || true' EXIT

wait_http() {
  local url="$1"
  local timeout="$2"
  local i
  for ((i = 0; i < timeout; i++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_portforward() {
  pkill -f "port-forward -n ${NS} svc/auth-service ${AUTH_PORT}:8080" >/dev/null 2>&1 || true
  pkill -f "port-forward -n ${NS} svc/api-service ${API_PORT}:8080" >/dev/null 2>&1 || true

  microk8s kubectl port-forward -n "${NS}" svc/auth-service "${AUTH_PORT}:8080" >"${TMP_DIR}/pf-auth.log" 2>&1 &
  PF_AUTH=$!
  microk8s kubectl port-forward -n "${NS}" svc/api-service "${API_PORT}:8080" >"${TMP_DIR}/pf-api.log" 2>&1 &
  PF_API=$!

  wait_http "http://127.0.0.1:${AUTH_PORT}/health" 60 || echo "[WARN] auth health not ready"
  wait_http "http://127.0.0.1:${API_PORT}/health" 60 || echo "[WARN] api health not ready"
}

run_case() {
  local case_name="$1"
  local action="$2"
  local json_out="${OUTPUT_DIR}/fault-${case_name}-${STAMP}.json"
  local k6_log="${TMP_DIR}/k6-${case_name}.log"

  echo "[INFO] Case: ${case_name}"
  k6 run --no-thresholds \
    -e AUTH_BASE="http://127.0.0.1:${AUTH_PORT}" \
    -e API_BASE="http://127.0.0.1:${API_PORT}" \
    --out json="${json_out}" \
    "${ROOT_DIR}/RealisticServices/k6/realistic-flow.js" >"${k6_log}" 2>&1 &
  local k6_pid=$!

  sleep "${INJECT_DELAY}"
  local t0
  t0="$(date +%s)"

  eval "${action}" || true

  local recovered=0
  local mttr=-1
  local i
  for ((i = 0; i < RECOVERY_TIMEOUT; i++)); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; then
      local t1
      t1="$(date +%s)"
      mttr=$((t1 - t0))
      recovered=1
      break
    fi
    sleep 1
  done

  wait "$k6_pid" || true

  python3 - "${OUT_CSV}" "${case_name}" "${json_out}" "${recovered}" "${mttr}" <<'PY'
import csv
import json
import math
import os
import sys

csv_path, case_name, json_path, recovered, mttr = sys.argv[1:6]
recovered = int(recovered)
mttr = int(mttr)

req_durations = []
failed_vals = []
checks = []

if os.path.exists(json_path):
    with open(json_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("type") != "Point":
                continue
            metric = row.get("metric")
            val = row.get("data", {}).get("value")
            if not isinstance(val, (int, float)):
                continue
            if metric == "http_req_duration":
                req_durations.append(float(val))
            elif metric == "http_req_failed":
                failed_vals.append(float(val))
            elif metric == "checks":
                checks.append(float(val))

def pctl(values, p):
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return values[int(k)]
    return values[f] * (c - k) + values[c] * (k - f)

p95 = pctl(req_durations, 95)
failed_rate = (sum(failed_vals) / len(failed_vals)) if failed_vals else None
success_rate = (1.0 - failed_rate) if failed_rate is not None else None
checks_rate = (sum(checks) / len(checks)) if checks else None

exists = os.path.exists(csv_path)
with open(csv_path, "a", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "scenario", "recovered", "mttr_seconds",
            "http_req_duration_p95_ms", "http_req_failed_rate",
            "request_success_rate", "checks_rate"
        ],
    )
    if not exists:
        writer.writeheader()
    writer.writerow({
        "scenario": case_name,
        "recovered": recovered,
        "mttr_seconds": mttr,
        "http_req_duration_p95_ms": f"{p95:.3f}" if p95 is not None else "",
        "http_req_failed_rate": f"{failed_rate:.6f}" if failed_rate is not None else "",
        "request_success_rate": f"{success_rate:.6f}" if success_rate is not None else "",
        "checks_rate": f"{checks_rate:.6f}" if checks_rate is not None else "",
    })
PY
}

start_portforward

run_case "restart-api" "microk8s kubectl rollout restart deployment/api-service -n ${NS} && microk8s kubectl rollout status deployment/api-service -n ${NS} --timeout=180s"
run_case "restart-data" "microk8s kubectl rollout restart deployment/data-service -n ${NS} && microk8s kubectl rollout status deployment/data-service -n ${NS} --timeout=180s"
run_case "restart-auth" "microk8s kubectl rollout restart deployment/auth-service -n ${NS} && microk8s kubectl rollout status deployment/auth-service -n ${NS} --timeout=180s"

python3 - "${OUT_CSV}" "${OUT_MD}" <<'PY'
import csv
import sys

csv_path, md_path = sys.argv[1:3]
rows = []
with open(csv_path, "r", newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

with open(md_path, "w", encoding="utf-8") as f:
    f.write("# Fault Tolerance Report\n\n")
    f.write("| Scenario | Recovered | MTTR (s) | P95 (ms) | Failed rate | Success rate | Checks rate |\n")
    f.write("|---|---:|---:|---:|---:|---:|---:|\n")
    for r in rows:
        f.write(
            f"| {r.get('scenario','')} | {r.get('recovered','')} | {r.get('mttr_seconds','')} | "
            f"{r.get('http_req_duration_p95_ms','')} | {r.get('http_req_failed_rate','')} | "
            f"{r.get('request_success_rate','')} | {r.get('checks_rate','')} |\n"
        )

print(md_path)
PY

echo "[INFO] Fault tolerance CSV: ${OUT_CSV}"
echo "[INFO] Fault tolerance report: ${OUT_MD}"
