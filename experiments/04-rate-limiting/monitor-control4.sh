#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Control 4 Monitor ==="
echo "Fecha: $(date +'%F %T')"
echo

echo "Procesos activos:"
pgrep -af "run-control4-safe.sh|run-control4-autopilot-safe.sh|run-baseline-safe.sh|run-rl-tests-safe.sh|k6 run" || echo "(sin procesos)"

echo
for s in baseline ratelimit; do
  c=$(ls -1 "$ROOT_DIR/results/$s"/*.json 2>/dev/null | wc -l || true)
  echo "- $s: $c"
done

echo
[[ -f "$ROOT_DIR/results/logs/control4-autopilot.log" ]] && tail -n 15 "$ROOT_DIR/results/logs/control4-autopilot.log"
