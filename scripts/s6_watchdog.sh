#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_PATH="$ROOT_DIR/Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv"
RESULTS_DIR="$ROOT_DIR/Testing/results/auto_runs/randomized_campaigns"
CAMPAIGN_CMD=(bash "$ROOT_DIR/scripts/run-s6-integrated-repro.sh" --execute --continue-on-readiness-fail)
LOG_PATH="$ROOT_DIR/s6_watchdog.log"
CHECK_INTERVAL=60
LOCK_DIR="$ROOT_DIR/.s6_watchdog.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_PATH"
}

count_total() {
  awk 'NR>1{n++} END{print n+0}' "$MATRIX_PATH"
}

count_complete() {
  python3 - <<'PY' "$MATRIX_PATH" "$RESULTS_DIR"
import csv
import datetime
import json
import os
import sys

matrix_path = sys.argv[1]
results_dir = sys.argv[2]

expected = []
with open(matrix_path, newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        expected.append(
            f"{row['campaign_id']}_{row['block_day']}_order{row['random_order']}_{row['control']}_{row['variant']}_{row['security_mode']}_{row['vus']}vus.json"
        )

def is_complete(path: str) -> bool:
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as fh:
            times = []
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get('type') != 'Point':
                    continue
                t = obj.get('data', {}).get('time')
                if t:
                    times.append(t)
    except FileNotFoundError:
        return False

    if len(times) < 10:
        return False

    def parse_iso(ts: str) -> datetime.datetime:
        fixed = ts.replace('Z', '+00:00')
        if '.' in fixed:
            prefix, rest = fixed.split('.', 1)
            if '+' in rest:
                frac, tz = rest.split('+', 1)
                fixed = f"{prefix}.{frac[:6]}+{tz}"
            elif '-' in rest:
                frac, tz = rest.split('-', 1)
                fixed = f"{prefix}.{frac[:6]}-{tz}"
        return datetime.datetime.fromisoformat(fixed)

    try:
        dur = (parse_iso(max(times)) - parse_iso(min(times))).total_seconds()
    except Exception:
        return False

    return dur >= 54

complete = 0
for name in expected:
    if is_complete(os.path.join(results_dir, name)):
        complete += 1

print(complete)
PY
}

is_campaign_running() {
  pgrep -f "scripts/run-s6-integrated-repro.sh --execute --continue-on-readiness-fail" >/dev/null 2>&1
}

main() {
  # Singleton guard: allow only one watchdog instance.
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
  else
    if [[ -f "$LOCK_DIR/pid" ]]; then
      lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        log "another watchdog is already running (pid=$lock_pid); exiting"
        exit 0
      fi
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo $$ > "$LOCK_DIR/pid"
  fi

  trap 'rm -rf "$LOCK_DIR"' EXIT

  log "watchdog started"
  local total
  total="$(count_total)"
  log "target total runs: ${total}"

  while true; do
    local complete
    complete="$(count_complete)"

    if [[ "$complete" -ge "$total" ]]; then
      log "campaign complete: ${complete}/${total}. watchdog exiting."
      exit 0
    fi

    if is_campaign_running; then
      log "campaign running: ${complete}/${total}"
    else
      log "campaign stopped at ${complete}/${total}. restarting..."
      (
        cd "$ROOT_DIR"
        nohup "${CAMPAIGN_CMD[@]}" >> "$ROOT_DIR/s6_watchdog_campaign.log" 2>&1 &
      )
      log "restart dispatched"
    fi

    sleep "$CHECK_INTERVAL"
  done
}

main "$@"
