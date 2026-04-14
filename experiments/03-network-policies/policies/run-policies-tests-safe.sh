#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/results/policies"
LOG_DIR="$ROOT_DIR/results/logs"
TARGET_URL="${TARGET_URL:-http://localhost:30100/process}"
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

ensure_portforward() {
  if curl -s -o /dev/null -w '%{http_code}' -X POST "$TARGET_URL" -H 'Content-Type: application/json' -d '{}' | grep -qE '^(200|4[0-9]{2}|5[0-9]{2})$'; then
    return 0
  fi

  pkill -f "kubectl port-forward -n default svc/s0 30100:80" >/dev/null 2>&1 || true
  nohup microk8s kubectl port-forward -n default svc/s0 30100:80 >"$LOG_DIR/portforward-s0.log" 2>&1 &

  for _ in $(seq 1 15); do
    sleep 1
    if curl -s -o /dev/null -w '%{http_code}' -X POST "$TARGET_URL" -H 'Content-Type: application/json' -d '{}' | grep -qE '^(200|4[0-9]{2}|5[0-9]{2})$'; then
      return 0
    fi
  done

  echo "[policies-netpol] Warning: port-forward no estable"
  return 0
}

ensure_portforward

for vus in 5 10 20; do
  for rep in 1 2 3; do
    outfile="$RESULTS_DIR/policies-vus${vus}-rep${rep}.json"
    logfile="$LOG_DIR/policies-vus${vus}-rep${rep}.log"

    ensure_portforward
    echo "[policies-netpol] Ejecutando VUS=${vus} REP=${rep}"
    k6 run --no-thresholds \
      -e TARGET_URL="$TARGET_URL" \
      -e VUS="$vus" \
      -e DURATION="60s" \
      --out "json=$outfile" \
      "$ROOT_DIR/tests/test-netpol-policies.js" \
      >"$logfile" 2>&1 || true

    sleep 20
  done
done

echo "[policies-netpol] Finalizado"
