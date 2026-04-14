#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/results"
LOG_DIR="$RESULTS_DIR/logs"
LOG_FILE="$LOG_DIR/control4-autopilot.log"
LOCK_FILE="$RESULTS_DIR/.control4.lock"
mkdir -p "$LOG_DIR"
exec >>"$LOG_FILE" 2>&1

echo "[$(date +'%F %T')] [control4] Inicio"
if [[ -f "$LOCK_FILE" ]]; then
  echo "[$(date +'%F %T')] [control4] lock activo, saliendo"
  exit 1
fi
trap 'rm -f "$LOCK_FILE"' EXIT
printf '%s\n' "$$" > "$LOCK_FILE"

base_count=$(ls -1 "$RESULTS_DIR"/baseline/*.json 2>/dev/null | wc -l || true)
if (( base_count < 9 )); then
  echo "[$(date +'%F %T')] [control4] Ejecutando baseline"
  bash "$ROOT_DIR/run-control4-safe.sh" --scenario baseline
fi

rl_count=$(ls -1 "$RESULTS_DIR"/ratelimit/*.json 2>/dev/null | wc -l || true)
if (( rl_count < 9 )); then
  echo "[$(date +'%F %T')] [control4] Ejecutando rate limiting"
  bash "$ROOT_DIR/run-control4-safe.sh" --scenario ratelimit
fi

echo "[$(date +'%F %T')] [control4] Ejecutando analisis"
python3 "$ROOT_DIR/analysis/analyze-rl-results.py" --results-dir "$RESULTS_DIR" --output-dir "$ROOT_DIR/analysis/output-final"

echo "[$(date +'%F %T')] [control4] Fin"
