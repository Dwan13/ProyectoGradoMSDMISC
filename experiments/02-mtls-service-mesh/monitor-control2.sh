#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/results/logs"

echo "=== Control 2 Monitor ==="
echo "Fecha: $(date +'%F %T')"
echo

echo "Procesos activos:"
pgrep -af "run-control2-safe.sh|run-control2-autopilot-safe.sh|run-baseline-safe.sh|run-istio-tests-safe.sh|run-linkerd-tests-safe.sh|k6 run" || echo "(sin procesos)"
echo

echo "Conteo de resultados:"
for s in baseline istio linkerd; do
  c=$(ls -1 "$ROOT_DIR/results/$s"/*.json 2>/dev/null | wc -l || true)
  echo "- $s: $c"
done

echo
if [[ -f "$LOG_DIR/control2-baseline-run.log" ]]; then
  echo "Ultimas lineas baseline log:"
  tail -n 8 "$LOG_DIR/control2-baseline-run.log"
fi

echo
if [[ -f "$LOG_DIR/control2-autopilot.log" ]]; then
  echo "Ultimas lineas autopilot log:"
  tail -n 8 "$LOG_DIR/control2-autopilot.log"
fi
