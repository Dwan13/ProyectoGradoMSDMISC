#!/usr/bin/env bash
# ==============================================================================
# replicate-tomorrow.sh
#
# Procedimiento UNIFICADO de replicación para la campaña factorial.
# Ejecuta secuencialmente: encendido → bootstrap → (opcional) campaña.
#
# Diseñado para que mañana cualquiera (o tú mismo) pueda replicar TODO
# desde cero sin sorpresas.
#
# Modos:
#   --mode quick       Sanidad reducida: 12 escen × 2 VUS (1,5) × 2 rep = 48 runs (~50min)
#   --mode full        Campaña factorial completa: 12×4×8 = 384 runs (~7-9h)
#   --mode bootstrap   Solo encendido + bootstrap (no lanza campaña)
#   --mode dry-run     Imprime el plan sin ejecutar nada
#
# Opciones:
#   --duration N       Segundos de carga por run (default 60)
#   --warmup N         Segundos de estabilización pre-run (default 15)
#   --out-dir PATH     Directorio de resultados (default Testing/results/factorial_campaign/<ts>)
#   --skip-startup     No reinicia MicroK8s (asume que ya está activo)
#   --shutdown-after   Apagar MicroK8s al terminar
#   --yes              No pedir confirmaciones
#
# Ejemplos:
#   bash scripts/replicate-tomorrow.sh --mode quick --yes
#   bash scripts/replicate-tomorrow.sh --mode full --yes --shutdown-after
#   bash scripts/replicate-tomorrow.sh --mode bootstrap
#   bash scripts/replicate-tomorrow.sh bootstrap --yes
#   bash scripts/replicate-tomorrow.sh --mode dry-run
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="bootstrap"
DURATION=60
WARMUP=15
OUT_DIR=""
SKIP_STARTUP=false
SHUTDOWN_AFTER=false
ASSUME_YES=false

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[replicate]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*"; exit 1; }

usage() { sed -n '2,40p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)            MODE="$2"; shift 2 ;;
    --duration)        DURATION="$2"; shift 2 ;;
    --warmup)          WARMUP="$2"; shift 2 ;;
    --out-dir)         OUT_DIR="$2"; shift 2 ;;
    --skip-startup)    SKIP_STARTUP=true; shift ;;
    --shutdown-after)  SHUTDOWN_AFTER=true; shift ;;
    --yes)             ASSUME_YES=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    quick|full|bootstrap|dry-run)
      if [[ "$MODE" != "bootstrap" ]]; then
        fail "modo ya especificado: $MODE"
      fi
      MODE="$1"
      shift
      ;;
    *) fail "opción desconocida: $1" ;;
  esac
done

case "$MODE" in
  quick|full|bootstrap|dry-run) ;;
  *) fail "--mode debe ser quick|full|bootstrap|dry-run" ;;
esac

# ─── BANNER ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  REPLICACIÓN µBench — Campaña Factorial"
echo "  Diseño: 4 controles × 3 variantes × 4 cargas × 8 réplicas"
echo "  Total:  384 runs (modo full) | 48 runs (modo quick)"
echo "============================================================"
echo ""
echo "Configuración:"
echo "  • Modo:           $MODE"
echo "  • Duración/run:   ${DURATION}s"
echo "  • Warmup/run:     ${WARMUP}s"
echo "  • Skip startup:   $SKIP_STARTUP"
echo "  • Shutdown final: $SHUTDOWN_AFTER"
echo "  • Resultados:     ${OUT_DIR:-auto}"
echo ""

if [[ "$MODE" == "dry-run" ]]; then
  log "DRY-RUN: imprimiendo plan sin ejecutar"
  python3 "${SCRIPT_DIR}/run-factorial-campaign.py" --dry-run \
    --vus 1 5 10 20 --replicas 8 --duration "$DURATION" --warmup "$WARMUP"
  exit 0
fi

if [[ "$ASSUME_YES" == "false" ]]; then
  read -r -p "Continuar con --mode $MODE? [Enter=sí, n=no]: " ans
  [[ "$ans" =~ ^[Nn] ]] && { warn "cancelado"; exit 1; }
fi

T_START=$(date +%s)

# ─── 1) Encendido ────────────────────────────────────────────────────────────
if [[ "$SKIP_STARTUP" == "false" ]]; then
  log "[1/3] Encendido (factorial-graceful-startup.sh)"
  STARTUP_ARGS=(--yes)
  bash "${SCRIPT_DIR}/factorial-graceful-startup.sh" "${STARTUP_ARGS[@]}"
else
  log "[1/3] Encendido OMITIDO (--skip-startup); validando cluster"
  microk8s status >/dev/null 2>&1 || fail "MicroK8s no está corriendo"
  bash "${SCRIPT_DIR}/factorial-bootstrap.sh" --skip-smoke
fi
ok "Cluster en estado BASELINE"

# ─── 2) Campaña ──────────────────────────────────────────────────────────────
case "$MODE" in
  bootstrap)
    log "[2/3] modo=bootstrap → no se lanza campaña"
    ;;

  quick)
    log "[2/3] Campaña QUICK (48 runs, ~50 min con duration=${DURATION})"
    QUICK_ARGS=(--vus 1 5 --replicas 2 --duration "$DURATION" --warmup "$WARMUP")
    [[ -n "$OUT_DIR" ]] && QUICK_ARGS+=(--out-dir "$OUT_DIR")
    python3 "${SCRIPT_DIR}/run-factorial-campaign.py" "${QUICK_ARGS[@]}"
    ;;

  full)
    log "[2/3] Campaña FULL (384 runs, ~$((384 * (DURATION + WARMUP + 5) / 3600))h estimado)"
    FULL_ARGS=(--vus 1 5 10 20 --replicas 8 --duration "$DURATION" --warmup "$WARMUP")
    [[ -n "$OUT_DIR" ]] && FULL_ARGS+=(--out-dir "$OUT_DIR")
    python3 "${SCRIPT_DIR}/run-factorial-campaign.py" "${FULL_ARGS[@]}"
    ;;
esac

T_END=$(date +%s)
ELAPSED=$((T_END - T_START))
ok "Tiempo total: $((ELAPSED/3600))h $(( (ELAPSED%3600)/60 ))m $((ELAPSED%60))s"

# ─── 3) Apagado opcional ─────────────────────────────────────────────────────
if [[ "$SHUTDOWN_AFTER" == "true" ]]; then
  log "[3/3] Apagado (graceful-shutdown.sh --yes)"
  bash "${SCRIPT_DIR}/graceful-shutdown.sh" --yes || warn "shutdown reportó issue"
else
  log "[3/3] Apagado OMITIDO (cluster sigue activo)"
fi

echo ""
echo "============================================================"
echo "  ✓ REPLICACIÓN COMPLETADA"
echo "============================================================"
echo ""
echo "Resultados en: ${OUT_DIR:-${ROOT_DIR}/Testing/results/factorial_campaign/}"
echo ""
echo "Análisis sugerido:"
echo "  ls -lh Testing/results/factorial_campaign/"
echo "  python3 -c \"import pandas as pd; df=pd.read_csv('Testing/results/factorial_campaign/<dir>/results_factorial.csv'); print(df.groupby(['control','variant'])[['avg_ms','p95_ms','rps','cpu_mcores','mem_mib']].mean().round(2))\""
echo ""
