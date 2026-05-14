#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/Testing/results/scaling_tests"
K6_SCRIPT="$ROOT_DIR/Testing/baseline.js"
TARGET_URL="${TARGET_URL:-http://127.0.0.1:31213/s0}"
DURATION="${DURATION:-60s}"
BENCH_PROFILE="${BENCH_PROFILE:-native}"
VUS_STAGES=(1 5 10 20)
REPORT="$RESULTS_DIR/scaling-report_mubench-advanced_$(date +%Y%m%d).csv"

mkdir -p "$RESULTS_DIR"

echo "scenario,control,variant,vus,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib" > "$REPORT"

duration_to_seconds() {
  local d="$1"
  if [[ "$d" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$d" =~ ^([0-9]+)m$ ]]; then
    echo "$(( ${BASH_REMATCH[1]} * 60 ))"
    return
  fi
  if [[ "$d" =~ ^([0-9]+)h$ ]]; then
    echo "$(( ${BASH_REMATCH[1]} * 3600 ))"
    return
  fi

  # Fallback conservador para formatos no contemplados
  echo "60"
}

parse_k6_jsonl() {
  local json_file="$1"
  local duration_secs="$2"
  python3 - << PY
import json
f = "$json_file"
duration_secs = float($duration_secs)
durations=[]
failed=0
total_failed_pts=0
reqs=0
with open(f) as fh:
  for line in fh:
    try:
      o=json.loads(line)
    except Exception:
      continue
    if o.get('type')!='Point':
      continue
    m=o.get('metric')
    v=o.get('data',{}).get('value',0)
    if m=='http_req_duration':
      durations.append(float(v))
    elif m=='http_req_failed':
      total_failed_pts += 1
      failed += int(v)
    elif m=='http_reqs':
      reqs += int(v)
durations.sort()
avg = sum(durations)/len(durations) if durations else 0
p95 = durations[min(int(len(durations)*0.95), len(durations)-1)] if durations else 0
err = (failed/total_failed_pts*100) if total_failed_pts else 0
rps = reqs/duration_secs if duration_secs > 0 else 0
print(f"{avg:.2f} {p95:.2f} {err:.2f} {rps:.2f}")
PY
}

node_resources() {
  kubectl top nodes 2>/dev/null | tail -1 | awk '{
    cpu=$2; mem=$4;
    gsub(/m$/, "", cpu); gsub(/Mi$/, "", mem);
    print cpu " " mem
  }' || echo "0 0"
}

duration_secs="$(duration_to_seconds "$DURATION")"
echo "Running scenario 3 scaling against $TARGET_URL"
echo "Benchmark profile: $BENCH_PROFILE"
for vus in "${VUS_STAGES[@]}"; do
  out="$RESULTS_DIR/scaling_scenario3_${vus}vus_$(date +%s).json"
  echo "- VUS=$vus"
  k6 run \
    -e TARGET_URL="$TARGET_URL" \
    -e VUS="$vus" \
    -e DURATION="$DURATION" \
    -e BENCH_PROFILE="$BENCH_PROFILE" \
    --out json="$out" \
    "$K6_SCRIPT" >/tmp/scenario3_k6_${vus}.log 2>&1 || true

  read -r avg p95 err rps < <(parse_k6_jsonl "$out" "$duration_secs")
  read -r cpu mem < <(node_resources)
  cpu="${cpu:-0}"; mem="${mem:-0}"

  echo "mubench-advanced,S3,advanced,$vus,$avg,$p95,$err,$rps,$cpu,$mem" >> "$REPORT"
done

echo "Report: $REPORT"
cat "$REPORT"
