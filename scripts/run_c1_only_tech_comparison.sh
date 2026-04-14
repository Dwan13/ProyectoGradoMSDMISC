#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXP_DIR="${ROOT_DIR}/experiments/01-api-gateway"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/Testing/results/c1-only-${STAMP}"
QOS_CSV="${OUT_DIR}/c1-qos-comparison.csv"
FAULT_CSV="${OUT_DIR}/c1-fault-tolerance.csv"
SUMMARY_MD="${OUT_DIR}/c1-summary.md"

VUS_LIST="${VUS_LIST:-10 25 50}"
DURATION="${DURATION:-60s}"
FAULT_VUS="${FAULT_VUS:-20}"
FAULT_DURATION="${FAULT_DURATION:-120s}"
FAULT_INJECT_DELAY="${FAULT_INJECT_DELAY:-15}"

BASELINE_PORT="${BASELINE_PORT:-30084}"
NGINX_URL="${NGINX_URL:-http://127.0.0.1:30080}"
KONG_URL="${KONG_URL:-http://127.0.0.1:30082/process}"

PF_S0_PID=""
PF_PROM_PID=""

log() { echo "[$(date +'%H:%M:%S')] $*"; }

cleanup() {
  if [[ -n "${PF_S0_PID}" ]]; then
    kill "${PF_S0_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PF_PROM_PID}" ]]; then
    kill "${PF_PROM_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_http() {
  local url="$1"
  local timeout="${2:-60}"
  local i
  for ((i=1; i<=timeout; i++)); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ensure_tools() {
  command -v k6 >/dev/null 2>&1 || { echo "[ERROR] k6 no esta instalado"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 no esta instalado"; exit 1; }
}

ensure_backends() {
  log "Verificando pods base de C1..."
  microk8s kubectl get pods -n default | grep -E 's0|s1|sdb1' >/dev/null
}

ensure_gateway_endpoints() {
  log "Validando endpoint NGINX ${NGINX_URL}/process"
  wait_http "${NGINX_URL}/health" 60
  curl -fsS -X POST "${NGINX_URL}/process" -H "Content-Type: application/json" -d '{}' >/dev/null

  log "Validando endpoint Kong ${KONG_URL}"
  wait_http "http://127.0.0.1:30082/health" 60
  curl -fsS -X POST "${KONG_URL}" -H "Content-Type: application/json" -d '{}' >/dev/null
}

start_baseline_portforward() {
  pkill -f "port-forward -n default svc/s0 ${BASELINE_PORT}:80" >/dev/null 2>&1 || true
  microk8s kubectl port-forward -n default svc/s0 "${BASELINE_PORT}:80" >/tmp/c1-baseline-pf.log 2>&1 &
  PF_S0_PID=$!
  wait_http "http://127.0.0.1:${BASELINE_PORT}/health" 60
}

run_k6_case() {
  local tech="$1"
  local vus="$2"
  local summary_json="${OUT_DIR}/summary-${tech}-vus${vus}.json"
  local raw_json="${OUT_DIR}/raw-${tech}-vus${vus}.json"
  local script=""
  local target=""

  case "$tech" in
    baseline)
      script="${EXP_DIR}/tests/baseline.js"
      target="http://127.0.0.1:${BASELINE_PORT}/process"
      ;;
    kong)
      script="${EXP_DIR}/tests/test-kong.js"
      target="${KONG_URL}"
      ;;
    nginx)
      script="${EXP_DIR}/tests/test-nginx.js"
      target="${NGINX_URL}"
      ;;
    *)
      echo "[ERROR] tecnologia no soportada: ${tech}" >&2
      exit 1
      ;;
  esac

  log "k6 ${tech} vus=${vus} duration=${DURATION}"
  k6 run --no-thresholds \
    -e TARGET_URL="${target}" \
    -e VUS="${vus}" \
    -e DURATION="${DURATION}" \
    --summary-export "${summary_json}" \
    --out json="${raw_json}" \
    "${script}" >/tmp/c1-k6-${tech}-${vus}.log 2>&1
}

export_resource_snapshots() {
  local res_dir="${OUT_DIR}/resources"
  mkdir -p "${res_dir}"

  if ! curl -fsS "http://127.0.0.1:9090/-/ready" >/dev/null 2>&1; then
    log "Prometheus local no disponible; iniciando port-forward temporal"
    microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >/tmp/c1-prom-pf.log 2>&1 &
    PF_PROM_PID=$!
    wait_http "http://127.0.0.1:9090/-/ready" 60 || true
  fi

  log "Exportando CPU/memoria namespace default"
  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace default --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090"

  log "Exportando CPU/memoria namespace kong"
  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace kong --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090" || true

  log "Exportando CPU/memoria namespace ingress"
  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace ingress --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090" || true
}

run_fault_case() {
  local tech="$1"
  local target=""
  local script=""
  local health_url=""
  local raw_json="${OUT_DIR}/fault-raw-${tech}.json"

  case "$tech" in
    baseline)
      script="${EXP_DIR}/tests/baseline.js"
      target="http://127.0.0.1:${BASELINE_PORT}/process"
      health_url="http://127.0.0.1:${BASELINE_PORT}/health"
      ;;
    kong)
      script="${EXP_DIR}/tests/test-kong.js"
      target="${KONG_URL}"
      health_url="http://127.0.0.1:30082/health"
      ;;
    nginx)
      script="${EXP_DIR}/tests/test-nginx.js"
      target="${NGINX_URL}"
      health_url="${NGINX_URL}/health"
      ;;
    *)
      echo "[ERROR] tecnologia no soportada en fault: ${tech}" >&2
      exit 1
      ;;
  esac

  log "Fault test ${tech}: restart de s0 durante carga"
  k6 run --no-thresholds \
    -e TARGET_URL="${target}" \
    -e VUS="${FAULT_VUS}" \
    -e DURATION="${FAULT_DURATION}" \
    --out json="${raw_json}" \
    "${script}" >/tmp/c1-fault-${tech}.log 2>&1 &
  local k6_pid=$!

  sleep "${FAULT_INJECT_DELAY}"
  local t0
  t0="$(date +%s)"
  microk8s kubectl rollout restart deployment/s0 -n default >/dev/null
  microk8s kubectl rollout status deployment/s0 -n default --timeout=240s >/dev/null || true

  local recovered=0
  local mttr=-1
  local i
  for ((i=0; i<240; i++)); do
    if curl -fsS --max-time 3 "${health_url}" >/dev/null 2>&1; then
      local t1
      t1="$(date +%s)"
      recovered=1
      mttr=$((t1 - t0))
      break
    fi
    sleep 1
  done

  wait "${k6_pid}" || true

  python3 - "${FAULT_CSV}" "${tech}" "${raw_json}" "${recovered}" "${mttr}" <<'PY'
import csv
import json
import math
import os
import sys

csv_path, tech, raw_json, recovered, mttr = sys.argv[1:6]
recovered = int(recovered)
mttr = int(mttr)

req_dur = []
failed = []
checks = []
http_reqs = 0
tmin = None
tmax = None

if os.path.exists(raw_json):
    with open(raw_json, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get('type') != 'Point':
                continue
            metric = row.get('metric')
            data = row.get('data', {})
            val = data.get('value')
            ts = data.get('time')
            if ts:
                if tmin is None or ts < tmin:
                    tmin = ts
                if tmax is None or ts > tmax:
                    tmax = ts
            if metric == 'http_req_duration' and isinstance(val, (int, float)):
                req_dur.append(float(val))
            elif metric == 'http_req_failed' and isinstance(val, (int, float)):
                failed.append(float(val))
            elif metric == 'checks' and isinstance(val, (int, float)):
                checks.append(float(val))
            elif metric == 'http_reqs':
                http_reqs += 1

def pctl(arr, p):
    if not arr:
        return None
    arr = sorted(arr)
    k = (len(arr)-1) * (p/100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return arr[int(k)]
    return arr[f]*(c-k) + arr[c]*(k-f)

p95 = pctl(req_dur, 95)
failed_rate = (sum(failed)/len(failed)) if failed else None
checks_rate = (sum(checks)/len(checks)) if checks else None
success_rate = (1.0 - failed_rate) if failed_rate is not None else None

exists = os.path.exists(csv_path)
with open(csv_path, 'a', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=[
        'technology', 'fault_scenario', 'recovered', 'mttr_seconds',
        'http_req_duration_p95_ms', 'http_req_failed_rate',
        'request_success_rate', 'checks_rate', 'http_reqs_count'
    ])
    if not exists:
        w.writeheader()
    w.writerow({
        'technology': tech,
        'fault_scenario': 'restart-s0',
        'recovered': recovered,
        'mttr_seconds': mttr,
        'http_req_duration_p95_ms': f"{p95:.3f}" if p95 is not None else '',
        'http_req_failed_rate': f"{failed_rate:.6f}" if failed_rate is not None else '',
        'request_success_rate': f"{success_rate:.6f}" if success_rate is not None else '',
        'checks_rate': f"{checks_rate:.6f}" if checks_rate is not None else '',
        'http_reqs_count': http_reqs,
    })
PY
}

build_qos_csv() {
  python3 - "${OUT_DIR}" "${QOS_CSV}" <<'PY'
import csv
import glob
import json
import os
import re
import sys

out_dir, out_csv = sys.argv[1:3]
rows = []
for path in sorted(glob.glob(os.path.join(out_dir, 'summary-*-vus*.json'))):
    m = re.search(r'summary-(.+)-vus(\d+)\.json$', os.path.basename(path))
    if not m:
        continue
    tech = m.group(1)
    vus = int(m.group(2))
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    met = data.get('metrics', {})
    def get_metric(metric, key, alt=''):
        obj = met.get(metric, {})
        if not isinstance(obj, dict):
            return ''
        values = obj.get('values')
        if isinstance(values, dict):
            val = values.get(key)
            if val is not None:
                return val
            if alt:
                val = values.get(alt)
                if val is not None:
                    return val
        val = obj.get(key)
        if val is not None:
            return val
        if alt:
            val = obj.get(alt)
            if val is not None:
                return val
        return ''
    rows.append({
        'technology': tech,
        'vus': vus,
        'http_reqs_count': get_metric('http_reqs', 'count'),
        'http_reqs_rate_rps': get_metric('http_reqs', 'rate'),
        'avg_ms': get_metric('http_req_duration', 'avg'),
        'p95_ms': get_metric('http_req_duration', 'p(95)'),
        'p99_ms': get_metric('http_req_duration', 'p(99)'),
        'http_req_failed_rate': get_metric('http_req_failed', 'rate', 'value'),
        'checks_rate': get_metric('checks', 'rate', 'value'),
    })

rows.sort(key=lambda r: (r['technology'], int(r['vus'])))
with open(out_csv, 'w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=[
        'technology', 'vus', 'http_reqs_count', 'http_reqs_rate_rps',
        'avg_ms', 'p95_ms', 'p99_ms', 'http_req_failed_rate', 'checks_rate'
    ])
    w.writeheader()
    w.writerows(rows)
print(out_csv)
PY
}

build_summary_md() {
  python3 - "${QOS_CSV}" "${FAULT_CSV}" "${SUMMARY_MD}" <<'PY'
import csv
import os
import sys

qos_csv, fault_csv, md_path = sys.argv[1:4]

qos = []
if os.path.exists(qos_csv):
    with open(qos_csv, 'r', encoding='utf-8') as f:
        qos = list(csv.DictReader(f))

fault = []
if os.path.exists(fault_csv):
    with open(fault_csv, 'r', encoding='utf-8') as f:
        fault = list(csv.DictReader(f))

with open(md_path, 'w', encoding='utf-8') as f:
    f.write('# C1 Technology Comparison Summary\n\n')
    f.write('## QoS (k6)\n\n')
    f.write('| Tech | VUS | Avg (ms) | P95 (ms) | P99 (ms) | Throughput (rps) | Failed rate | Checks rate |\n')
    f.write('|---|---:|---:|---:|---:|---:|---:|---:|\n')
    for r in qos:
      f.write(f"| {r['technology']} | {r['vus']} | {float(r['avg_ms'] or 0):.3f} | {float(r['p95_ms'] or 0):.3f} | {float(r['p99_ms'] or 0):.3f} | {float(r['http_reqs_rate_rps'] or 0):.3f} | {float(r['http_req_failed_rate'] or 0):.6f} | {float(r['checks_rate'] or 0):.6f} |\n")

    f.write('\n## Fault Tolerance (restart s0)\n\n')
    f.write('| Tech | Recovered | MTTR (s) | P95 (ms) | Failed rate | Success rate | Checks rate | Requests |\n')
    f.write('|---|---:|---:|---:|---:|---:|---:|---:|\n')
    for r in fault:
      f.write(f"| {r['technology']} | {r['recovered']} | {r['mttr_seconds']} | {float(r['http_req_duration_p95_ms'] or 0):.3f} | {float(r['http_req_failed_rate'] or 0):.6f} | {float(r['request_success_rate'] or 0):.6f} | {float(r['checks_rate'] or 0):.6f} | {r['http_reqs_count']} |\n")

print(md_path)
PY
}

main() {
  mkdir -p "${OUT_DIR}"
  ensure_tools
  ensure_backends
  ensure_gateway_endpoints
  start_baseline_portforward

  log "Iniciando barrido QoS C1 (baseline/kong/nginx)"
  for tech in baseline kong nginx; do
    for vus in ${VUS_LIST}; do
      run_k6_case "$tech" "$vus"
    done
  done

  log "Construyendo CSV de QoS"
  build_qos_csv

  log "Ejecutando fault tolerance por tecnologia"
  for tech in baseline kong nginx; do
    run_fault_case "$tech"
  done

  log "Exportando metricas de recursos CPU/memoria"
  export_resource_snapshots

  log "Construyendo resumen markdown"
  build_summary_md

  log "Listo. Artefactos en: ${OUT_DIR}"
  echo "QOS_CSV=${QOS_CSV}"
  echo "FAULT_CSV=${FAULT_CSV}"
  echo "SUMMARY_MD=${SUMMARY_MD}"
}

main "$@"
