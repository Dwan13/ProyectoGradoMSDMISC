#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_DIR="${ROOT_DIR}/RealisticServices"
K6_SCRIPT="${REAL_DIR}/k6/users-bulk-create-list.js"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/Testing/results/c4-realistic-${STAMP}"
QOS_CSV="${OUT_DIR}/c4-realistic-qos.csv"
FAULT_CSV="${OUT_DIR}/c4-realistic-fault.csv"
RESOURCE_BY_TECH_CSV="${OUT_DIR}/c4-realistic-resource-by-tech.csv"
SUMMARY_MD="${OUT_DIR}/c4-realistic-summary.md"

CREATE_VUS="${CREATE_VUS:-15}"
CREATE_DURATION="${CREATE_DURATION:-45s}"
LIST_START="${LIST_START:-50s}"
LIST_VUS="${LIST_VUS:-5}"
LIST_DURATION="${LIST_DURATION:-25s}"
LIST_LIMIT="${LIST_LIMIT:-100}"

FAULT_VUS="${FAULT_VUS:-20}"
FAULT_DURATION="${FAULT_DURATION:-120s}"
FAULT_INJECT_DELAY="${FAULT_INJECT_DELAY:-15}"
KEEP_RAW_JSON="${KEEP_RAW_JSON:-0}"
AUTO_CLEANUP_RESULTS="${AUTO_CLEANUP_RESULTS:-1}"
KEEP_RUNS="${KEEP_RUNS:-1}"

PF_AUTH_PID=""
PF_API_PID=""
PF_PROM_PID=""

log() { echo "[$(date +'%H:%M:%S')] $*"; }

cleanup() {
  kill "${PF_AUTH_PID:-}" "${PF_API_PID:-}" "${PF_PROM_PID:-}" >/dev/null 2>&1 || true
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

rollout_api() {
  microk8s kubectl rollout restart deployment/api-service -n realistic >/dev/null
  microk8s kubectl rollout status deployment/api-service -n realistic --timeout=240s >/dev/null
}

apply_c4_none() {
  microk8s kubectl set env deployment/api-service -n realistic RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 >/dev/null
  rollout_api
}

apply_c4_moderate() {
  microk8s kubectl set env deployment/api-service -n realistic RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=120 >/dev/null
  rollout_api
}

apply_c4_strict() {
  microk8s kubectl set env deployment/api-service -n realistic RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=60 >/dev/null
  rollout_api
}

ensure_prometheus() {
  if curl -fsS "http://127.0.0.1:9090/-/ready" >/dev/null 2>&1; then
    return 0
  fi
  pkill -f "port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090" >/dev/null 2>&1 || true
  microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >/tmp/c4r-prom-pf.log 2>&1 &
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

  ensure_prometheus

  local realistic_cpu
  local realistic_mem_bytes

  realistic_cpu="$(query_prom_scalar 'sum(rate(container_cpu_usage_seconds_total{namespace="realistic",container!="",pod!=""}[2m]))')"
  realistic_mem_bytes="$(query_prom_scalar 'sum(container_memory_working_set_bytes{namespace="realistic",container!="",pod!=""})')"

  python3 - "${RESOURCE_BY_TECH_CSV}" "${tech}" "${realistic_cpu}" "${realistic_mem_bytes}" <<'PY'
import csv
import os
import sys

csv_path, tech, real_cpu, real_mem_b = sys.argv[1:5]
real_cpu = float(real_cpu or 0)
real_mem_b = float(real_mem_b or 0)

real_mem_mib = real_mem_b / (1024 * 1024)

exists = os.path.exists(csv_path)
with open(csv_path, 'a', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    if not exists:
        w.writerow([
            'technology',
            'realistic_cpu_cores',
            'e2e_cpu_cores',
            'realistic_mem_mib',
            'e2e_mem_mib',
        ])
    w.writerow([
        tech,
        f"{real_cpu:.6f}",
        f"{real_cpu:.6f}",
        f"{real_mem_mib:.3f}",
        f"{real_mem_mib:.3f}",
    ])
PY
}

start_baseline_pf() {
  kill "${PF_AUTH_PID:-}" "${PF_API_PID:-}" >/dev/null 2>&1 || true
  pkill -f "port-forward -n realistic svc/auth-service 18082:8080" >/dev/null 2>&1 || true
  pkill -f "port-forward -n realistic svc/api-service 18081:8080" >/dev/null 2>&1 || true

  microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080 >/tmp/c4r-auth-pf.log 2>&1 &
  PF_AUTH_PID=$!
  microk8s kubectl port-forward -n realistic svc/api-service 18081:8080 >/tmp/c4r-api-pf.log 2>&1 &
  PF_API_PID=$!

  wait_http "http://127.0.0.1:18082/health" 80
  wait_http "http://127.0.0.1:18081/health" 80
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
      "${K6_SCRIPT}" >/tmp/c4r-${tech}.log 2>&1; then
      return 0
    fi

    echo "[WARN] users-bulk ${tech} fallo en intento ${attempt}; reintentando" >&2
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
    "${K6_SCRIPT}" >/tmp/c4r-fault-${tech}.log 2>&1 &
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
            data = row.get('data', {})
            metric = row.get('metric') or data.get('metric', '')
            value = data.get('value')
            if value is None:
                continue
            try:
                value = float(value)
            except Exception:
                continue
            if metric == 'http_req_duration':
                durations.append(value)
            elif metric == 'http_req_failed':
                failed.append(value)
            elif metric == 'checks':
                checks.append(value)

def p95(values):
    if not values:
        return 0.0
    values = sorted(values)
    idx = int(math.ceil(0.95 * len(values))) - 1
    idx = max(0, min(idx, len(values) - 1))
    return values[idx]

failed_rate = (sum(failed) / len(failed)) if failed else 0.0
success_rate = 1.0 - failed_rate
checks_rate = (sum(checks) / len(checks)) if checks else 0.0
p95_ms = p95(durations)

exists = os.path.exists(csv_path)
with open(csv_path, 'a', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    if not exists:
        w.writerow([
            'technology',
            'fault_scenario',
            'recovered',
            'mttr_seconds',
            'http_req_duration_p95_ms',
            'http_req_failed_rate',
            'request_success_rate',
            'checks_rate',
        ])
    w.writerow([
        tech,
        'restart-api-service',
        recovered,
        mttr,
        f"{p95_ms:.3f}",
        f"{failed_rate:.6f}",
        f"{success_rate:.6f}",
        f"{checks_rate:.6f}",
    ])
PY
}

build_qos_csv() {
  python3 - "${OUT_DIR}" "${QOS_CSV}" <<'PY'
import csv
import json
import os
import sys

out_dir, qos_csv = sys.argv[1:3]

rows = []
for fn in os.listdir(out_dir):
    if not fn.startswith('summary-') or not fn.endswith('.json'):
        continue
    tech = fn[len('summary-'):-len('.json')]
    path = os.path.join(out_dir, fn)
    try:
        obj = json.load(open(path, 'r', encoding='utf-8'))
    except Exception:
        continue

    metrics = obj.get('metrics', {})

    def get_metric_value(metric_name, key, default=0.0):
      m = metrics.get(metric_name, {})
      if isinstance(m, dict) and key in m and isinstance(m.get(key), (int, float)):
          return float(m.get(key))
      vals = m.get('values', {}) if isinstance(m, dict) else {}
      if isinstance(vals, dict) and key in vals and isinstance(vals.get(key), (int, float)):
          return float(vals.get(key))
      return float(default)

    http_count = get_metric_value('http_reqs', 'count')
    http_rate = get_metric_value('http_reqs', 'rate')
    avg_ms = get_metric_value('http_req_duration', 'avg')
    p95_ms = get_metric_value('http_req_duration', 'p(95)')
    p99_ms = get_metric_value('http_req_duration', 'p(99)')
    failed_rate = get_metric_value('http_req_failed', 'value')
    checks_rate = get_metric_value('checks', 'rate')

    users_created = get_metric_value('users_created_total', 'count')
    users_listed = get_metric_value('users_listed_total', 'count')
    users_create_p95 = get_metric_value('users_create_duration', 'p(95)')
    users_list_p95 = get_metric_value('users_list_duration', 'p(95)')

    rows.append([
        tech,
        int(http_count),
        http_rate,
        avg_ms,
        p95_ms,
        p99_ms,
        failed_rate,
        checks_rate,
        int(users_created),
        int(users_listed),
        users_create_p95,
        users_list_p95,
    ])

rows.sort(key=lambda r: r[0])

with open(qos_csv, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow([
        'technology',
        'http_reqs_count',
        'http_reqs_rate_rps',
        'avg_ms',
        'p95_ms',
        'p99_ms',
        'http_req_failed_rate',
        'checks_rate',
        'users_created_total',
        'users_listed_total',
        'users_create_p95_ms',
        'users_list_p95_ms',
    ])
    w.writerows(rows)

print(qos_csv)
PY
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
    f.write('# C4 Realistic Technology Comparison\n\n')
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

    f.write('\n## Recursos por tecnica (comparacion E2E)\n\n')
    f.write('| Tech | Realistic CPU | E2E CPU | Realistic Mem (MiB) | E2E Mem (MiB) |\n')
    f.write('|---|---:|---:|---:|---:|\n')
    for r in resource:
        f.write('| {} | {:.4f} | {:.4f} | {:.2f} | {:.2f} |\n'.format(
            r['technology'],
            float(r['realistic_cpu_cores'] or 0),
            float(r['e2e_cpu_cores'] or 0),
            float(r['realistic_mem_mib'] or 0),
            float(r['e2e_mem_mib'] or 0),
        ))

print(md_path)
PY
}

main() {
  mkdir -p "${OUT_DIR}"
  ensure_tools

  log "[1/9] Baseline realistic"
  apply_c4_none
  start_baseline_pf
  run_users_bulk_case baseline-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081"
  capture_resource_snapshot baseline-realistic

  log "[2/9] C4 ratelimit moderate (120 rpm)"
  apply_c4_moderate
  start_baseline_pf
  run_users_bulk_case c4-ratelimit-120-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081"
  capture_resource_snapshot c4-ratelimit-120-realistic

  log "[3/9] C4 ratelimit strict (60 rpm)"
  apply_c4_strict
  start_baseline_pf
  run_users_bulk_case c4-ratelimit-60-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081"
  capture_resource_snapshot c4-ratelimit-60-realistic

  log "[4/9] Consolidando QoS"
  build_qos_csv

  log "[5/9] Fault baseline"
  apply_c4_none
  start_baseline_pf
  run_fault_case baseline-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081" "http://127.0.0.1:18081/health"

  log "[6/9] Fault C4 moderate"
  apply_c4_moderate
  start_baseline_pf
  run_fault_case c4-ratelimit-120-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081" "http://127.0.0.1:18081/health"

  log "[7/9] Fault C4 strict"
  apply_c4_strict
  start_baseline_pf
  run_fault_case c4-ratelimit-60-realistic "http://127.0.0.1:18082" "http://127.0.0.1:18081" "http://127.0.0.1:18081/health"

  log "[8/9] Resumen final"
  build_summary_md

  if [[ "${KEEP_RAW_JSON}" != "1" ]]; then
    log "Post-proceso: eliminando raw JSON pesados"
    rm -f "${OUT_DIR}"/raw-*.json "${OUT_DIR}"/fault-raw-*.json || true
  fi

  if [[ "${AUTO_CLEANUP_RESULTS}" == "1" ]] && [[ -x "${ROOT_DIR}/scripts/cleanup_results.sh" ]]; then
    log "Post-proceso: limpieza de historico (keep-runs=${KEEP_RUNS})"
    if [[ "${KEEP_RAW_JSON}" == "1" ]]; then
      KEEP_RUNS="${KEEP_RUNS}" DELETE_RAW_IN_KEPT="0" "${ROOT_DIR}/scripts/cleanup_results.sh" --keep-runs "${KEEP_RUNS}" >/tmp/c4r-cleanup.log 2>&1 || true
    else
      KEEP_RUNS="${KEEP_RUNS}" DELETE_RAW_IN_KEPT="1" "${ROOT_DIR}/scripts/cleanup_results.sh" --keep-runs "${KEEP_RUNS}" >/tmp/c4r-cleanup.log 2>&1 || true
    fi
  fi

  log "[9/9] Limpiando C4 (baseline)"
  apply_c4_none

  echo "OUT_DIR=${OUT_DIR}"
  echo "QOS_CSV=${QOS_CSV}"
  echo "FAULT_CSV=${FAULT_CSV}"
  echo "RESOURCE_BY_TECH_CSV=${RESOURCE_BY_TECH_CSV}"
  echo "SUMMARY_MD=${SUMMARY_MD}"
}

main "$@"
