#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Control 3 Monitor ==="
echo "Fecha: $(date +'%F %T')"
echo

echo "Procesos activos:"
pgrep -af "run-control3-safe.sh|run-control3-autopilot-safe.sh|run-baseline-safe.sh|run-policies-tests-safe.sh|k6 run" || echo "(sin procesos)"

echo
for s in baseline policies; do
  c=$(ls -1 "$ROOT_DIR/results/$s"/*.json 2>/dev/null | wc -l || true)
  echo "- $s: $c"
done

echo
[[ -f "$ROOT_DIR/results/logs/control3-autopilot.log" ]] && tail -n 12 "$ROOT_DIR/results/logs/control3-autopilot.log"
