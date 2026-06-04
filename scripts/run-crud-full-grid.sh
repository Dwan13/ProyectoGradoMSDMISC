#!/usr/bin/env bash
# ============================================================================
# run-crud-full-grid.sh
#
# Corre la matriz COMPLETA del experimento CRUD:
#   4 controles (C1, C2, C3, C4) x 3 variantes c/u  = 12 escenarios
#   x VUS levels: 1, 5, 10, 20                       = 4 niveles
#   x REPLICAS repeticiones por escenario            = N (default 3)
#   duracion de cada replica: 20s + WARMUP
#
# Total reps = 12 * 4 * REPLICAS  (con REPLICAS=8 -> 384 reps)
#
# Uso:
#   nohup bash scripts/run-crud-full-grid.sh > /tmp/crud-full-grid.log 2>&1 &
#   tail -f /tmp/crud-full-grid.log
#
# Override defaults:
#   REPLICAS=5 DURATION=30s VUS_LEVELS="1 5 10 20 50" \
#     bash scripts/run-crud-full-grid.sh
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="${ROOT_DIR}/scripts/run-crud-experiment.sh"

# ---- Parametrizable via env ------------------------------------------------
VUS_LEVELS="${VUS_LEVELS:-1 5 10 20}"
REPLICAS="${REPLICAS:-8}"
DURATION="${DURATION:-20s}"
WARMUP="${WARMUP:-10s}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"

STAMP="$(date +%Y%m%d_%H%M%S)"
GRID_DIR="${ROOT_DIR}/Testing/results/auto_runs/crud_grid_${STAMP}"
mkdir -p "$GRID_DIR"
MASTER_LOG="${GRID_DIR}/grid.log"
MASTER_CSV="${GRID_DIR}/results_all.csv"
MASTER_RES="${GRID_DIR}/resource_metrics_all.csv"

log()  { echo -e "\033[0;34m[grid]\033[0m $(date +%H:%M:%S) $*" | tee -a "$MASTER_LOG"; }
ok()   { echo -e "\033[0;32m[ ok ]\033[0m $*" | tee -a "$MASTER_LOG"; }
err()  { echo -e "\033[0;31m[fail]\033[0m $*" | tee -a "$MASTER_LOG"; }

log "===================================================================="
log "Grid: 12 escenarios x VUS={${VUS_LEVELS}} x REPLICAS=${REPLICAS}"
log "Duracion=${DURATION}  Warmup=${WARMUP}"
log "Salida: ${GRID_DIR}"
log "===================================================================="
# Preflight obligatorio: aborta si el entorno no garantiza reproducibilidad
if [[ "$SKIP_PREFLIGHT" != "1" ]]; then
  log ""
  log "Ejecutando preflight-check..."
  if ! bash "${ROOT_DIR}/scripts/preflight-check.sh" 2>&1 | tee -a "$MASTER_LOG"; then
    err "PREFLIGHT FALLÓ → abortando grid (use SKIP_PREFLIGHT=1 para ignorar bajo tu propio riesgo)"
    exit 2
  fi
  ok "preflight OK → iniciando grid"
else
  log "SKIP_PREFLIGHT=1 → preflight omitido (no se garantiza reproducibilidad)"
fi
TOTAL=0
N_LEVELS=$(echo "$VUS_LEVELS" | wc -w)
TOTAL_EXPECTED=$(( 12 * REPLICAS * N_LEVELS ))
log "Reps totales esperadas: ${TOTAL_EXPECTED}"

START_TS=$(date +%s)

for VUS in $VUS_LEVELS; do
  log ""
  log "######  VUS=${VUS}  ######"
  if bash "$ORCH" --vus "$VUS" --replicas "$REPLICAS" --duration "$DURATION" --warmup "$WARMUP" \
        2>&1 | tee -a "$MASTER_LOG"; then
    ok "VUS=${VUS} terminado"
  else
    err "VUS=${VUS} fallo (exit=$?), continuo con el siguiente nivel"
  fi

  # localizar la run dir generada por el orquestador (la mas reciente que matchea)
  LAST_RUN=$(ls -1dt "${ROOT_DIR}/Testing/results/auto_runs/crud_vus${VUS}_n${REPLICAS}_"* 2>/dev/null | head -1 || true)
  if [[ -n "$LAST_RUN" && -f "$LAST_RUN/results.csv" ]]; then
    if [[ ! -f "$MASTER_CSV" ]]; then
      head -1 "$LAST_RUN/results.csv" > "$MASTER_CSV"
    fi
    tail -n +2 "$LAST_RUN/results.csv" >> "$MASTER_CSV"
    if [[ -f "$LAST_RUN/resource_metrics.csv" ]]; then
      [[ -f "$MASTER_RES" ]] || head -1 "$LAST_RUN/resource_metrics.csv" > "$MASTER_RES"
      tail -n +2 "$LAST_RUN/resource_metrics.csv" >> "$MASTER_RES"
    fi
    ROWS=$(( $(wc -l < "$MASTER_CSV") - 1 ))
    TOTAL=$ROWS
    ok "Acumulado: ${TOTAL}/${TOTAL_EXPECTED} reps  (run: $(basename "$LAST_RUN"))"
  else
    err "No encontre results.csv para VUS=${VUS}"
  fi
done

END_TS=$(date +%s)
ELAPSED=$(( END_TS - START_TS ))
log ""
log "===================================================================="
log "Grid FINALIZADO en ${ELAPSED}s (~$((ELAPSED/60)) min)"
log "Reps recolectadas: ${TOTAL}/${TOTAL_EXPECTED}"
log "Resultados consolidados:"
log "  ${MASTER_CSV}"
log "  ${MASTER_RES}"
log "  ${MASTER_LOG}"
log "===================================================================="
