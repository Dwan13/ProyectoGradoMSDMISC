#!/usr/bin/env bash
set -euo pipefail

################################################################################
# graceful-shutdown.sh
#
# Script para apagar la máquina de forma segura sin perder el estado útil
# para el día siguiente.
# - Guarda snapshot de estado y escenario seleccionado
# - Detiene procesos locales (k6 / port-forward)
# - Escala deployments a 0 de forma opcional (no borra recursos)
# - Detiene MicroK8s opcionalmente
#
# Uso:
#   bash scripts/graceful-shutdown.sh --scenario s2
#   bash scripts/graceful-shutdown.sh --scenario s4 --keep-running
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${ROOT_DIR}/.mubench-state"
STATE_FILE="${STATE_DIR}/last-session.env"

SCENARIO=""
STOP_MICROK8S=true
SCALE_DOWN=true
ASSUME_YES=false

usage() {
  cat << EOF
Uso: bash scripts/graceful-shutdown.sh [opciones]

Opciones:
  --scenario <s1|s2|s3|s4>   Escenario activo para restaurar manana
  --keep-running              No detener MicroK8s
  --no-scale-down             No escalar deployments a 0
  --yes                       Omitir confirmacion interactiva
  -h, --help                  Mostrar ayuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --keep-running)
      STOP_MICROK8S=false
      shift
      ;;
    --no-scale-down)
      SCALE_DOWN=false
      shift
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcion desconocida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$SCENARIO" ]] && [[ ! "$SCENARIO" =~ ^s[1-4]$ ]]; then
  echo "Escenario invalido: $SCENARIO (usa s1|s2|s3|s4)" >&2
  exit 1
fi

confirm_shutdown_plan() {
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi

  echo ""
  log_warn "Se aplicara shutdown operativo con las siguientes opciones:"
  echo "  • Escenario registrado: ${SCENARIO:-unknown}"
  echo "  • Escalar deployments a 0: ${SCALE_DOWN}"
  echo "  • Detener MicroK8s: ${STOP_MICROK8S}"
  echo ""
  read -r -p "Escribe APAGAR para continuar: " confirm
  if [[ "$confirm" != "APAGAR" ]]; then
    log_warn "Operacion cancelada por el usuario"
    exit 1
  fi
}

save_state() {
  mkdir -p "$STATE_DIR"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    echo "LAST_SHUTDOWN_UTC=$ts"
    echo "LAST_SCENARIO=${SCENARIO:-unknown}"
    echo "STOP_MICROK8S=${STOP_MICROK8S}"
    echo "SCALE_DOWN=${SCALE_DOWN}"
    echo "REPO_ROOT=${ROOT_DIR}"
  } > "$STATE_FILE"

  if command -v microk8s >/dev/null 2>&1 && microk8s status >/dev/null 2>&1; then
    local ns
    for ns in realistic mubench-real mubench-advanced mubench-s4 monitoring; do
      if microk8s kubectl get ns "$ns" >/dev/null 2>&1; then
        microk8s kubectl get deploy -n "$ns" \
          -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas \
          --no-headers 2>/dev/null | while read -r name replicas; do
            [[ -z "$name" ]] && continue
            echo "DEPLOY_${ns}_${name}=${replicas:-0}" | tr '-' '_' >> "$STATE_FILE"
          done
      fi
    done
  fi

  log_success "Snapshot guardado en: $STATE_FILE"
}

banner() {
  echo ""
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║${NC}        GRACEFUL SHUTDOWN - µBench Project            ${YELLOW}║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

banner

# Check if MicroK8s is running
if ! command -v microk8s &> /dev/null; then
  log_warn "MicroK8s no está instalado, nada que hacer"
  exit 0
fi

log_info "Iniciando shutdown graceful..."
echo ""

confirm_shutdown_plan

################################################################################
# Step 0: Guardar estado de la sesion
################################################################################

log_info "Paso 0/5: Guardando estado para restauracion..."
save_state
echo ""

################################################################################
# Step 1: Detener tests en ejecución (si los hay)
################################################################################

log_info "Paso 1/5: Verificando procesos en ejecucion..."

if pgrep -u "$USER" -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls\|live-control-and-request.sh" > /dev/null; then
  log_warn "Hay scripts de test en ejecución"
  log_info "Esperando a que terminen (máx 60s)..."
  
  sleep 5
  
  if pgrep -u "$USER" -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls\|live-control-and-request.sh" > /dev/null; then
    log_warn "Tests aun en ejecucion, terminando..."
    pkill -u "$USER" -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls\|live-control-and-request.sh" || true
    sleep 2
  fi
fi

# Cerrar port-forward para evitar sesiones colgadas
pkill -u "$USER" -f "kubectl port-forward" >/dev/null 2>&1 || true
pkill -u "$USER" -f "microk8s kubectl port-forward" >/dev/null 2>&1 || true

log_success "Procesos limpios"
echo ""

################################################################################
# Step 2: Preservar recursos Kubernetes
################################################################################

log_info "Paso 2/5: Preservando recursos Kubernetes (sin borrar pods/PVs)..."
log_success "Recursos preservados"
echo ""

################################################################################
# Step 3: Detener servicios críticos
################################################################################

log_info "Paso 3/5: Deteniendo servicios..."

if [[ "$SCALE_DOWN" == "true" ]]; then
  for ns in realistic mubench-real mubench-advanced mubench-s4 monitoring; do
    if microk8s kubectl get ns "$ns" &>/dev/null 2>&1; then
      log_info "  -> Escalando deployments a 0 en namespace '$ns'..."
      microk8s kubectl scale deployment --all -n "$ns" --replicas=0 2>/dev/null || true
    fi
  done
else
  log_info "  -> Omitido (--no-scale-down)"
fi

log_success "Servicios detenidos"
echo ""

################################################################################
# Step 4: Detener MicroK8s
################################################################################

log_info "Paso 4/5: Deteniendo MicroK8s..."

if [[ "$STOP_MICROK8S" == "true" ]] && microk8s status &>/dev/null 2>&1; then
  log_info "  → Parando MicroK8s..."
  microk8s stop 2>/dev/null || true
  
  # Esperar a que se detenga completamente
  log_info "  → Esperando detención completa (máx 30s)..."
  for i in {1..30}; do
    if ! microk8s status &>/dev/null 2>&1; then
      log_success "MicroK8s detenido exitosamente"
      break
    fi
    sleep 1
  done
  if microk8s status &>/dev/null 2>&1; then
    log_warn "MicroK8s sigue activo tras timeout de espera; revisa con: microk8s status"
  fi
elif [[ "$STOP_MICROK8S" == "false" ]]; then
  log_warn "MicroK8s se mantiene activo (--keep-running)"
else
  log_warn "MicroK8s ya está detenido"
fi

echo ""

################################################################################
# Step 5: Información final
################################################################################

log_info "Paso 5/5: Información final..."

cat << EOF

${GREEN}✓ SHUTDOWN GRACEFUL COMPLETADO${NC}

Estado:
  • Procesos k6/scripts: Terminados
  • Recursos Kubernetes: PRESERVADOS
  • Servicios: $( [[ "$SCALE_DOWN" == "true" ]] && echo "Escalados a 0 (si existian)" || echo "Sin cambios (--no-scale-down)" )
  • MicroK8s: $( [[ "$STOP_MICROK8S" == "true" ]] && echo "Parado" || echo "Activo" )

Recursos limpios:
  • Data en volúmenes: PRESERVADO (para mañana)
  • Configuración: PRESERVADA
  • Snapshot: ${STATE_FILE}

Próximos pasos:
  1. Ahora puedes apagar la máquina sin problema
  2. Manana al encender, ejecuta: bash scripts/graceful-startup.sh
  3. Si quieres forzar escenario: bash scripts/graceful-startup.sh --scenario s2

${YELLOW}Nota:${NC} Todos tus datos y configuración se preservaron.

EOF

log_success "¡Listo! Máquina segura para apagar"
