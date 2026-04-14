#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_DIR="${ROOT_DIR}/RealisticServices"
K6_SCRIPT="${REAL_DIR}/k6/users-bulk-create-list.js"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/Testing/results/c1-realistic-${STAMP}"
QOS_CSV="${OUT_DIR}/c1-realistic-qos.csv"
FAULT_CSV="${OUT_DIR}/c1-realistic-fault.csv"
RESOURCE_BY_TECH_CSV="${OUT_DIR}/c1-realistic-resource-by-tech.csv"
SUMMARY_MD="${OUT_DIR}/c1-realistic-summary.md"

CREATE_VUS="${CREATE_VUS:-15}"
CREATE_DURATION="${CREATE_DURATION:-45s}"
LIST_START="${LIST_START:-50s}"
LIST_VUS="${LIST_VUS:-5}"
LIST_DURATION="${LIST_DURATION:-25s}"
LIST_LIMIT="${LIST_LIMIT:-100}"

FAULT_VUS="${FAULT_VUS:-20}"
FAULT_DURATION="${FAULT_DURATION:-120s}"
FAULT_INJECT_DELAY="${FAULT_INJECT_DELAY:-15}"

PF_AUTH_PID=""
PF_API_PID=""
PF_ING_PID=""
PF_PROM_PID=""

log() { echo "[$(date +'%H:%M:%S')] $*"; }

cleanup() {
  kill "${PF_AUTH_PID:-}" "${PF_API_PID:-}" "${PF_ING_PID:-}" "${PF_PROM_PID:-}" >/dev/null 2>&1 || true
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

ensure_prometheus() {
  if curl -fsS "http://127.0.0.1:9090/-/ready" >/dev/null 2>&1; then
    return 0
  fi
  pkill -f "port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090" >/dev/null 2>&1 || true
  microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >/tmp/c1r-prom-pf.log 2>&1 &
  PF_PROM_PID=$!
  wait_http "http://127.0.0.1:9090/-/ready" 60
}

query_prom_scalar() {
  local expr="$1"
  local out
  out="$(curl -fsSG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=${expr}" || true)"
  python3 - "$out" <<'PY'
import json
import sys

raw = sys.argv[1]
if not raw:
    print("0")
    raise SystemExit(0)

try:
    obj = json.loads(raw)
    result = obj.get("data", {}).get("result", [])
    if not result:
        print("0")
    else:
        print(result[0].get("value", [None, "0"])[1])
except Exception:
    print("0")
PY
}

capture_resource_snapshot() {
  local tech="$1"
  local include_gateway_ns="${2:-}"

  ensure_prometheus

  local cpu_real mem_real cpu_gate mem_gate cpu_total mem_total
  cpu_real="$(query_prom_scalar 'sum(rate(container_cpu_usage_seconds_total{namespace="realistic",container!="",pod!=""}[1m]))')"
  mem_real="$(query_prom_scalar 'sum(container_memory_working_set_bytes{namespace="realistic",container!="",pod!=""})/(1024*1024)')"

  cpu_gate="0"
  mem_gate="0"
  if [[ -n "${include_gateway_ns}" ]]; then
    cpu_gate="$(query_prom_scalar "sum(rate(container_cpu_usage_seconds_total{namespace=\"${include_gateway_ns}\",container!=\"\",pod!=\"\"}[1m]))")"
    mem_gate="$(query_prom_scalar "sum(container_memory_working_set_bytes{namespace=\"${include_gateway_ns}\",container!=\"\",pod!=\"\"})/(1024*1024)")"
  fi

  cpu_total="$(python3 - <<PY
real=float('${cpu_real}' or 0)
gate=float('${cpu_gate}' or 0)
print(real+gate)
PY
)"
  mem_total="$(python3 - <<PY
real=float('${mem_real}' or 0)
gate=float('${mem_gate}' or 0)
print(real+gate)
PY
)"

  python3 - "${RESOURCE_BY_TECH_CSV}" "${tech}" "${cpu_real}" "${mem_real}" "${cpu_gate}" "${mem_gate}" "${cpu_total}" "${mem_total}" <<'PY'
import csv
import os
import sys

csv_path, tech, cpu_real, mem_real, cpu_gate, mem_gate, cpu_total, mem_total = sys.argv[1:9]
exists = os.path.exists(csv_path)
with open(csv_path, "a", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=[
        "technology", "realistic_cpu_cores", "realistic_mem_mib",
        "gateway_cpu_cores", "gateway_mem_mib", "e2e_cpu_cores", "e2e_mem_mib"
    ])
    if not exists:
        w.writeheader()
    w.writerow({
        "technology": tech,
        "realistic_cpu_cores": cpu_real,
        "realistic_mem_mib": mem_real,
        "gateway_cpu_cores": cpu_gate,
        "gateway_mem_mib": mem_gate,
        "e2e_cpu_cores": cpu_total,
        "e2e_mem_mib": mem_total,
    })
PY
}

start_baseline_pf() {
  pkill -f "port-forward -n realistic svc/auth-service 18082:8080" >/dev/null 2>&1 || true
  pkill -f "port-forward -n realistic svc/api-service 18081:8080" >/dev/null 2>&1 || true

  microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/c1r-auth-pf.log 2>&1 &
  PF_AUTH_PID=$!
  microk8s kubectl port-forward -n realistic svc/api-service 18081:8080 >/tmp/c1r-api-pf.log 2>&1 &
  PF_API_PID=$!

  wait_http "http://127.0.0.1:18082/health" 60
  wait_http "http://127.0.0.1:18081/health" 60
}

start_ingress_pf() {
  if wait_http "http://127.0.0.1:30080/auth/health" 10 && wait_http "http://127.0.0.1:30080/api/health" 10; then
    return 0
  fi

  local ingress_svc=""
  for candidate in ingress nginx-ingress-controller nginx-ingress-microk8s-controller; do
    if microk8s kubectl -n ingress get svc "${candidate}" >/dev/null 2>&1; then
      ingress_svc="${candidate}"
      break
    fi
  done

  if [[ -z "${ingress_svc}" ]]; then
    echo "[ERROR] No se encontro service de ingress en namespace ingress" >&2
    return 1
  fi

  pkill -f "port-forward -n ingress service/${ingress_svc} 32080:80" >/dev/null 2>&1 || true
  microk8s kubectl -n ingress port-forward "service/${ingress_svc}" 32080:80 >/tmp/c1r-ing-pf.log 2>&1 &
  PF_ING_PID=$!
  wait_http "http://127.0.0.1:32080/auth/health" 80
  wait_http "http://127.0.0.1:32080/api/health" 80
}

run_users_bulk_case() {
  local tech="$1"
  local auth_base="$2"
  local api_base="$3"
  local summary_json="${OUT_DIR}/summary-${tech}.json"
  local raw_json="${OUT_DIR}/raw-${tech}.json"
  local attempts="${RUN_RETRIES:-3}"
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    wait_http "${auth_base}/health" 60 || true
    wait_http "${api_base}/health" 60 || true

    log "Running realistic users-bulk for ${tech} (attempt ${attempt}/${attempts})"
    if k6 run --no-thresholds \
      -e AUTH_BASE="${auth_base}" \
      -e API_BASE="${api_base}" \
      -e CREATE_VUS="${CREATE_VUS}" \
      -e CREATE_DURATION="${CREATE_DURATION}" \
      -e LIST_START="${LIST_START}" \
      -e LIST_VUS="${LIST_VUS}" \
      -e LIST_DURATION="${LIST_DURATION}" \
      -e LIST_LIMIT="${LIST_LIMIT}" \
      --summary-export "${summary_json}" \
      --out json="${raw_json}" \
      "${K6_SCRIPT}" >/tmp/c1r-${tech}.log 2>&1; then
      return 0
    fi

    warn_msg="[WARN] users-bulk ${tech} fallo en intento ${attempt}; reintentando"
    echo "${warn_msg}" >&2
    sleep 3
  done

  echo "[ERROR] users-bulk ${tech} fallo tras ${attempts} intentos" >&2
  return 1
}

run_fault_case() {
  local tech="$1"
  local auth_base="$2"
  local api_base="$3"
  local api_health="$4"
  local raw_json="${OUT_DIR}/fault-raw-${tech}.json"

  log "Fault test ${tech}: restart de api-service durante users-bulk"
  k6 run --no-thresholds \
    -e AUTH_BASE="${auth_base}" \
    -e API_BASE="${api_base}" \
    -e CREATE_VUS="${FAULT_VUS}" \
    -e CREATE_DURATION="${FAULT_DURATION}" \
    -e LIST_START="20s" \
    -e LIST_VUS="${FAULT_VUS}" \
    -e LIST_DURATION="${FAULT_DURATION}" \
    -e LIST_LIMIT="${LIST_LIMIT}" \
    --out json="${raw_json}" \
    "${K6_SCRIPT}" >/tmp/c1r-fault-${tech}.log 2>&1 &
  local k6_pid=$!

  sleep "${FAULT_INJECT_DELAY}"
  local t0
  t0="$(date +%s)"
  microk8s kubectl rollout restart deployment/api-service -n realistic >/dev/null
  microk8s kubectl rollout status deployment/api-service -n realistic --timeout=240s >/dev/null || true

  local recovered=0
  local mttr=-1
  local i
  for ((i=0; i<240; i++)); do
    if curl -fsS --max-time 3 "${api_health}" >/dev/null 2>&1; then
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

durations = []
failed = []
checks = []

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
            val = row.get('data', {}).get('value')
            if not isinstance(val, (int, float)):
                continue
            if metric == 'http_req_duration':
                durations.append(float(val))
            elif metric == 'http_req_failed':
                failed.append(float(val))
            elif metric == 'checks':
                checks.append(float(val))

def pctl(arr, p):
    if not arr:
        return None
    arr = sorted(arr)
    k = (len(arr) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return arr[int(k)]
    return arr[f] * (c - k) + arr[c] * (k - f)

p95 = pctl(durations, 95)
failed_rate = (sum(failed) / len(failed)) if failed else None
checks_rate = (sum(checks) / len(checks)) if checks else None
success_rate = (1.0 - failed_rate) if failed_rate is not None else None

exists = os.path.exists(csv_path)
with open(csv_path, 'a', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=[
        'technology', 'fault_scenario', 'recovered', 'mttr_seconds',
        'http_req_duration_p95_ms', 'http_req_failed_rate',
        'request_success_rate', 'checks_rate'
    ])
    if not exists:
        w.writeheader()
    w.writerow({
        'technology': tech,
        'fault_scenario': 'restart-api-service',
        'recovered': recovered,
        'mttr_seconds': mttr,
        'http_req_duration_p95_ms': f'{p95:.3f}' if p95 is not None else '',
        'http_req_failed_rate': f'{failed_rate:.6f}' if failed_rate is not None else '',
        'request_success_rate': f'{success_rate:.6f}' if success_rate is not None else '',
        'checks_rate': f'{checks_rate:.6f}' if checks_rate is not None else '',
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

for path in sorted(glob.glob(os.path.join(out_dir, 'summary-*.json'))):
    m = re.search(r'summary-(.+)\.json$', os.path.basename(path))
    if not m:
        continue
    tech = m.group(1)
    with open(path, 'r', encoding='utf-8') as f:
        d = json.load(f)
    met = d.get('metrics', {})

    def g(metric, key, alt=''):
        x = met.get(metric, {})
        if not isinstance(x, dict):
            return ''
        vals = x.get('values')
        if isinstance(vals, dict):
            v = vals.get(key)
            if v is not None:
                return v
            if alt:
                v = vals.get(alt)
                if v is not None:
                    return v
        v = x.get(key)
        if v is not None:
            return v
        if alt:
            v = x.get(alt)
            if v is not None:
                return v
        return ''

    rows.append({
        'technology': tech,
        'http_reqs_count': g('http_reqs', 'count'),
        'http_reqs_rate_rps': g('http_reqs', 'rate'),
        'avg_ms': g('http_req_duration', 'avg'),
        'p95_ms': g('http_req_duration', 'p(95)'),
        'p99_ms': g('http_req_duration', 'p(99)'),
        'http_req_failed_rate': g('http_req_failed', 'rate', 'value'),
        'checks_rate': g('checks', 'rate', 'value'),
        'users_created_total': g('users_created_total', 'count', 'value'),
        'users_listed_total': g('users_listed_total', 'count', 'value'),
        'users_create_p95_ms': g('users_create_duration', 'p(95)'),
        'users_list_p95_ms': g('users_list_duration', 'p(95)'),
    })

rows.sort(key=lambda r: r['technology'])
with open(out_csv, 'w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=[
        'technology', 'http_reqs_count', 'http_reqs_rate_rps',
        'avg_ms', 'p95_ms', 'p99_ms', 'http_req_failed_rate', 'checks_rate',
        'users_created_total', 'users_listed_total', 'users_create_p95_ms', 'users_list_p95_ms'
    ])
    w.writeheader()
    w.writerows(rows)
print(out_csv)
PY
}

export_resources() {
  local res_dir="${OUT_DIR}/resources"
  mkdir -p "${res_dir}"

  if ! curl -fsS "http://127.0.0.1:9090/-/ready" >/dev/null 2>&1; then
    microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >/tmp/c1r-prom-pf.log 2>&1 &
    PF_PROM_PID=$!
    wait_http "http://127.0.0.1:9090/-/ready" 60 || true
  fi

  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace realistic --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090"
  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace kong --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090" || true
  bash "${ROOT_DIR}/scripts/export_resource_metrics.sh" --namespace ingress --window 10m --output-dir "${res_dir}" --prom-url "http://127.0.0.1:9090" || true
}

build_summary_md() {
  python3 - "${QOS_CSV}" "${FAULT_CSV}" "${RESOURCE_BY_TECH_CSV}" "${SUMMARY_MD}" <<'PY'
import csv
import os
import sys

qos_csv, fault_csv, resource_csv, md_path = sys.argv[1:5]
qos = list(csv.DictReader(open(qos_csv, 'r', encoding='utf-8'))) if os.path.exists(qos_csv) else []
fault = list(csv.DictReader(open(fault_csv, 'r', encoding='utf-8'))) if os.path.exists(fault_csv) else []
resource = list(csv.DictReader(open(resource_csv, 'r', encoding='utf-8'))) if os.path.exists(resource_csv) else []

with open(md_path, 'w', encoding='utf-8') as f:
    f.write('# C1 Realistic Technology Comparison\n\n')
    f.write('## QoS + Negocio (users create/list)\n\n')
    f.write('| Tech | HTTP avg (ms) | HTTP p95 (ms) | HTTP p99 (ms) | RPS | Failed rate | Checks rate | Created | Listed | Create p95 (ms) | List p95 (ms) |\n')
    f.write('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n')
    for r in qos:
        f.write('| {} | {:.3f} | {:.3f} | {:.3f} | {:.3f} | {:.6f} | {:.6f} | {} | {} | {:.3f} | {:.3f} |\n'.format(
            r['technology'],
            float(r['avg_ms'] or 0),
            float(r['p95_ms'] or 0),
            float(r['p99_ms'] or 0),
            float(r['http_reqs_rate_rps'] or 0),
            float(r['http_req_failed_rate'] or 0),
            float(r['checks_rate'] or 0),
            int(float(r['users_created_total'] or 0)),
            int(float(r['users_listed_total'] or 0)),
            float(r['users_create_p95_ms'] or 0),
            float(r['users_list_p95_ms'] or 0),
        ))

    f.write('\n## Fault Tolerance (restart api-service)\n\n')
    f.write('| Tech | Recovered | MTTR (s) | P95 (ms) | Failed rate | Success rate | Checks rate |\n')
    f.write('|---|---:|---:|---:|---:|---:|---:|\n')
    for r in fault:
        f.write('| {} | {} | {} | {:.3f} | {:.6f} | {:.6f} | {:.6f} |\n'.format(
            r['technology'], r['recovered'], r['mttr_seconds'],
            float(r['http_req_duration_p95_ms'] or 0),
            float(r['http_req_failed_rate'] or 0),
            float(r['request_success_rate'] or 0),
            float(r['checks_rate'] or 0),
        ))

    f.write('\n## Recursos por tecnologia (comparacion justa E2E)\n\n')
    f.write('| Tech | Realistic CPU | Gateway CPU | E2E CPU | Realistic Mem (MiB) | Gateway Mem (MiB) | E2E Mem (MiB) |\n')
    f.write('|---|---:|---:|---:|---:|---:|---:|\n')
    for r in resource:
        f.write('| {} | {:.4f} | {:.4f} | {:.4f} | {:.2f} | {:.2f} | {:.2f} |\n'.format(
            r['technology'],
            float(r['realistic_cpu_cores'] or 0),
            float(r['gateway_cpu_cores'] or 0),
            float(r['e2e_cpu_cores'] or 0),
            float(r['realistic_mem_mib'] or 0),
            float(r['gateway_mem_mib'] or 0),
            float(r['e2e_mem_mib'] or 0),
        ))

print(md_path)
PY
}

main() {
  mkdir -p "${OUT_DIR}"
  ensure_tools

  log "[1/7] Configurando baseline realistic"
  "${REAL_DIR}/controls/apply-control.sh" baseline
  start_baseline_pf
  run_users_bulk_case baseline-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081"
  capture_resource_snapshot baseline-realistic ""

  log "[2/7] Configurando C1 NGINX realistic"
  "${REAL_DIR}/controls/apply-control.sh" c1
  start_ingress_pf
  local nginx_auth="http://127.0.0.1:32080/auth"
  local nginx_api="http://127.0.0.1:32080/api"
  if wait_http "http://127.0.0.1:30080/auth/health" 2 && wait_http "http://127.0.0.1:30080/api/health" 2; then
    nginx_auth="http://127.0.0.1:30080/auth"
    nginx_api="http://127.0.0.1:30080/api"
  fi
  run_users_bulk_case nginx-realistic "${nginx_auth}" "${nginx_api}"
  capture_resource_snapshot nginx-realistic "ingress"

  log "[3/7] Configurando C1 Kong realistic"
  "${REAL_DIR}/controls/apply-control.sh" baseline
  bash "${ROOT_DIR}/scripts/configure_kong_realistic_routes.sh"
  run_users_bulk_case kong-realistic "http://127.0.0.1:30082/auth" "http://127.0.0.1:30082/api"
  capture_resource_snapshot kong-realistic "kong"

  log "[4/7] Consolidando QoS"
  build_qos_csv

  log "[5/7] Fault tolerance por tecnologia"
  "${REAL_DIR}/controls/apply-control.sh" baseline
  start_baseline_pf
  run_fault_case baseline-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081" "http://127.0.0.1:18081/health"

  "${REAL_DIR}/controls/apply-control.sh" c1
  start_ingress_pf
  nginx_auth="http://127.0.0.1:32080/auth"
  nginx_api="http://127.0.0.1:32080/api"
  if wait_http "http://127.0.0.1:30080/auth/health" 2 && wait_http "http://127.0.0.1:30080/api/health" 2; then
    nginx_auth="http://127.0.0.1:30080/auth"
    nginx_api="http://127.0.0.1:30080/api"
  fi
  run_fault_case nginx-realistic "${nginx_auth}" "${nginx_api}" "${nginx_api}/health"

  "${REAL_DIR}/controls/apply-control.sh" baseline
  bash "${ROOT_DIR}/scripts/configure_kong_realistic_routes.sh"
  run_fault_case kong-realistic "http://127.0.0.1:30082/auth" "http://127.0.0.1:30082/api" "http://127.0.0.1:30082/api/health"

  log "[6/7] Export de recursos"
  export_resources

  log "[7/7] Resumen final"
  build_summary_md

  echo "OUT_DIR=${OUT_DIR}"
  echo "QOS_CSV=${QOS_CSV}"
  echo "FAULT_CSV=${FAULT_CSV}"
  echo "RESOURCE_BY_TECH_CSV=${RESOURCE_BY_TECH_CSV}"
  echo "SUMMARY_MD=${SUMMARY_MD}"
}

main "$@"
