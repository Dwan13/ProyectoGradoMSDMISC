#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Uso: $0 --scenario {baseline|ratelimit}"
  exit 1
}

if [[ "${1:-}" != "--scenario" ]] || [[ $# -lt 2 ]]; then
  usage
fi

case "$2" in
  baseline)
    bash "$ROOT_DIR/baseline/run-baseline-safe.sh"
    ;;
  ratelimit)
    bash "$ROOT_DIR/ratelimit/apply-rate-limit-safe.sh"
    bash "$ROOT_DIR/ratelimit/run-rl-tests-safe.sh"
    ;;
  *)
    usage
    ;;
esac

echo "[control4] Escenario completado: $2"
