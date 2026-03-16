#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO="${1:-}"

usage() {
  echo "Uso: $0 --scenario {baseline|istio|linkerd}"
  exit 1
}

if [[ "$SCENARIO" != "--scenario" ]] || [[ $# -lt 2 ]]; then
  usage
fi

TARGET="$2"

case "$TARGET" in
  baseline)
    bash "$ROOT_DIR/baseline/run-baseline-safe.sh"
    ;;
  istio)
    bash "$ROOT_DIR/istio/install-istio-safe.sh"
    bash "$ROOT_DIR/istio/enable-mtls-strict.sh"
    bash "$ROOT_DIR/istio/run-istio-tests-safe.sh"
    ;;
  linkerd)
    bash "$ROOT_DIR/linkerd/install-linkerd-safe.sh"
    bash "$ROOT_DIR/linkerd/run-linkerd-tests-safe.sh"
    ;;
  *)
    usage
    ;;
esac

echo "[control2] Escenario completado: $TARGET"
