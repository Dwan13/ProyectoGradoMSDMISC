#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/results/ratelimit"
LOG_DIR="$ROOT_DIR/results/logs"
TARGET_URL="${TARGET_URL:-http://localhost:30080/rl-s0/process}"
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

for vus in 10 25 50; do
  for rep in 1 2 3; do
    outfile="$RESULTS_DIR/ratelimit-vus${vus}-rep${rep}.json"
    logfile="$LOG_DIR/ratelimit-vus${vus}-rep${rep}.log"

    echo "[ratelimit] Ejecutando VUS=${vus} REP=${rep}"
    k6 run --no-thresholds \
      -e TARGET_URL="$TARGET_URL" \
      -e VUS="$vus" \
      -e DURATION="60s" \
      --out "json=$outfile" \
      "$ROOT_DIR/tests/test-rl-enabled.js" \
      >"$logfile" 2>&1 || true

    sleep 20
  done
done

echo "[ratelimit] Finalizado"
