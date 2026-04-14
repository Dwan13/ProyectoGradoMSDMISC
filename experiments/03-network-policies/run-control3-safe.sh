#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Uso: $0 --scenario {baseline|policies}"
  exit 1
}

if [[ "${1:-}" != "--scenario" ]] || [[ $# -lt 2 ]]; then
  usage
fi

case "$2" in
  baseline)
    bash "$ROOT_DIR/baseline/run-baseline-safe.sh"
    ;;
  policies)
    bash "$ROOT_DIR/policies/apply-policies-safe.sh"
    bash "$ROOT_DIR/policies/run-policies-tests-safe.sh"
    bash "$ROOT_DIR/tests/test-lateral-blocking.sh"
    ;;
  *)
    usage
    ;;
esac

echo "[control3] Escenario completado: $2"
