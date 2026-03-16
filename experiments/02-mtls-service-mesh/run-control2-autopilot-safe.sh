#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/results"
LOG_DIR="$RESULTS_DIR/logs"
MASTER_LOG="$LOG_DIR/control2-autopilot.log"
LOCK_FILE="$RESULTS_DIR/.control2-autopilot.lock"
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$LOG_DIR"

exec >>"$MASTER_LOG" 2>&1

echo "[$(date +'%F %T')] [autopilot] Inicio Control 2"

if [[ -f "$LOCK_FILE" ]]; then
  echo "[$(date +'%F %T')] [autopilot] Lock detectado: $LOCK_FILE"
  echo "[$(date +'%F %T')] [autopilot] Saliendo para evitar ejecuciones duplicadas"
  exit 1
fi

trap 'rm -f "$LOCK_FILE"' EXIT
printf '%s\n' "$$" > "$LOCK_FILE"

wait_for_existing_runs() {
  local timeout=900
  local elapsed=0
  while pgrep -af "run-control2-safe.sh|run-baseline-safe.sh|run-istio-tests-safe.sh|run-linkerd-tests-safe.sh|k6 run" >/dev/null 2>&1; do
    if (( elapsed >= timeout )); then
      echo "[$(date +'%F %T')] [autopilot] Timeout esperando corridas existentes"
      break
    fi
    echo "[$(date +'%F %T')] [autopilot] Esperando corridas activas... (${elapsed}s)"
    sleep 15
    elapsed=$((elapsed + 15))
  done
}

run_safely() {
  local label="$1"
  local cmd="$2"
  echo "[$(date +'%F %T')] [autopilot] Ejecutando: $label"
  if bash -lc "$cmd"; then
    echo "[$(date +'%F %T')] [autopilot] OK: $label"
  else
    echo "[$(date +'%F %T')] [autopilot] ERROR: $label"
    return 1
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_existing_runs

# Baseline: corre si faltan archivos (esperados: 9)
base_count=$(ls -1 "$RESULTS_DIR"/baseline/*.json 2>/dev/null | wc -l || true)
echo "[$(date +'%F %T')] [autopilot] Baseline actuales: $base_count"
if (( base_count < 9 )); then
  run_safely "baseline" "cd '$ROOT_DIR' && bash run-control2-safe.sh --scenario baseline"
else
  echo "[$(date +'%F %T')] [autopilot] Baseline completo, se omite"
fi

# Istio
if has_cmd istioctl; then
  istio_count=$(ls -1 "$RESULTS_DIR"/istio/*.json 2>/dev/null | wc -l || true)
  echo "[$(date +'%F %T')] [autopilot] Istio actuales: $istio_count"
  if (( istio_count < 9 )); then
    run_safely "istio" "cd '$ROOT_DIR' && bash run-control2-safe.sh --scenario istio"
  else
    echo "[$(date +'%F %T')] [autopilot] Istio completo, se omite"
  fi
else
  echo "[$(date +'%F %T')] [autopilot] istioctl no encontrado, se omite Istio"
fi

# Linkerd
if has_cmd linkerd; then
  linkerd_count=$(ls -1 "$RESULTS_DIR"/linkerd/*.json 2>/dev/null | wc -l || true)
  echo "[$(date +'%F %T')] [autopilot] Linkerd actuales: $linkerd_count"
  if (( linkerd_count < 9 )); then
    run_safely "linkerd" "cd '$ROOT_DIR' && bash run-control2-safe.sh --scenario linkerd"
  else
    echo "[$(date +'%F %T')] [autopilot] Linkerd completo, se omite"
  fi
else
  echo "[$(date +'%F %T')] [autopilot] linkerd no encontrado, se omite Linkerd"
fi

# Analisis si hay al menos 1 escenario con datos
total_count=$(find "$RESULTS_DIR" -type f -name '*.json' | wc -l || true)
echo "[$(date +'%F %T')] [autopilot] Total JSON detectados: $total_count"
if (( total_count > 0 )); then
  run_safely "analysis" "cd '$ROOT_DIR' && python3 analysis/analyze-mtls-results.py --results-dir results --output-dir analysis/output"
else
  echo "[$(date +'%F %T')] [autopilot] Sin JSON para analizar"
fi

echo "[$(date +'%F %T')] [autopilot] Fin Control 2"
