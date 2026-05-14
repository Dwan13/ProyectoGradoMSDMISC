#!/usr/bin/env bash
set -euo pipefail

################################################################################
# graceful-startup.sh
#
# Script para levantar la maquina despues del apagado
# - Levanta MicroK8s
# - Restaura el ultimo escenario (o permite elegir uno)
# - Ejecuta el setup del escenario seleccionado
# - Verifica estado final para continuar pruebas
#
# Uso:
#   bash scripts/graceful-startup.sh
#   bash scripts/graceful-startup.sh --scenario s2
#   bash scripts/graceful-startup.sh --scenario last
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_FILE="${ROOT_DIR}/.mubench-state/last-session.env"

SCENARIO=""
AUTO_RESTORE=true
ASSUME_YES=false

usage() {
  cat << EOF
Uso: bash scripts/graceful-startup.sh [opciones]

Opciones:
  --scenario <s2|s3|s4|last>  Escenario a levantar
  --no-restore                    No usar snapshot previo
  --yes                           Omitir confirmacion antes de aplicar setup
  -h, --help                      Mostrar ayuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --no-restore)
      AUTO_RESTORE=false
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

scenario_menu() {
  echo ""
  echo "Selecciona escenario a levantar:"
  echo "  1) s2 - Postgres real"
  echo "  2) s3 - MuBench advanced"
  echo "  3) s4 - Semantic equivalent"
  echo "  4) last - Usar ultimo escenario guardado"
  read -r -p "Opcion [1-4]: " opt
  case "$opt" in
    1) SCENARIO="s2" ;;
    2) SCENARIO="s3" ;;
    3) SCENARIO="s4" ;;
    4) SCENARIO="last" ;;
    *)
      echo "Opcion invalida"
      exit 1
      ;;
  esac
}

load_last_scenario() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    if [[ -n "${LAST_SCENARIO:-}" ]] && [[ "${LAST_SCENARIO}" =~ ^s[2-4]$ ]]; then
      SCENARIO="$LAST_SCENARIO"
      log_info "Escenario restaurado desde snapshot: $SCENARIO"
      return 0
    fi
  fi
  return 1
}

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

run_scenario_setup() {
  local setup_script=""
  case "$SCENARIO" in
    s2)
      log_info "Levantando S2 (postgres real)..."
      setup_script="$SCRIPT_DIR/setup-postgres-real-scenario.sh"
      ;;
    s3)
      log_info "Levantando S3 (mubench advanced)..."
      setup_script="$SCRIPT_DIR/setup-scenario3-mubench-advanced.sh"
      ;;
    s4)
      log_info "Levantando S4 (semantic equivalent)..."
      setup_script="$SCRIPT_DIR/setup-scenario4-semantic-equivalent.sh"
      ;;
    *)
      log_error "Escenario invalido: $SCENARIO"
      exit 1
      ;;
  esac

  if [[ ! -x "$setup_script" ]]; then
    if [[ -f "$setup_script" ]]; then
      chmod +x "$setup_script" || true
    fi
  fi
  if [[ ! -f "$setup_script" ]]; then
    log_error "No se encontro script de setup: $setup_script"
    exit 1
  fi

  bash "$setup_script"
}

confirm_startup_plan() {
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi

  echo ""
  log_warn "Se aplicara setup del escenario '${SCENARIO}' sobre el cluster actual"
  read -r -p "Escribe ENCENDER para continuar: " confirm
  if [[ "$confirm" != "ENCENDER" ]]; then
    log_warn "Operacion cancelada por el usuario"
    exit 1
  fi
}

banner() {
  echo ""
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║${NC}        GRACEFUL STARTUP - µBench Project             ${YELLOW}║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

banner

if [[ -z "$SCENARIO" ]]; then
  if [[ "$AUTO_RESTORE" == "true" ]] && load_last_scenario; then
    :
  else
    scenario_menu
  fi
fi

if [[ "$SCENARIO" == "last" ]]; then
  if [[ "$AUTO_RESTORE" != "true" ]]; then
    log_error "--no-restore no permite usar --scenario last"
    exit 1
  fi
  if ! load_last_scenario; then
    log_warn "No hay escenario previo valido en $STATE_FILE"
    scenario_menu
  fi
fi

if [[ ! "$SCENARIO" =~ ^s[2-4]$ ]]; then
  log_error "Escenario invalido: $SCENARIO"
  exit 1
fi

################################################################################
# Step 1: Verificar MicroK8s instalado
################################################################################

log_info "Paso 1/6: Verificando MicroK8s..."

if ! command -v microk8s &> /dev/null; then
  log_error "MicroK8s no está instalado"
  log_info "Ejecuta: bash setup_mubench_env.sh"
  exit 1
fi

log_success "MicroK8s encontrado"
echo ""

################################################################################
# Step 2: Levantar MicroK8s
################################################################################

log_info "Paso 2/6: Levantando MicroK8s..."

microk8s start || log_warn "MicroK8s podría estar en recuperación..."

log_info "Esperando a que MicroK8s esté ready (máx 60s)..."

if ! microk8s status --wait-ready --timeout=300 &>/dev/null 2>&1; then
  log_warn "MicroK8s tardando, probando manualmente..."
  local_ready=false
  for i in {1..30}; do
    if microk8s status &>/dev/null 2>&1; then
      log_success "MicroK8s está ready"
      local_ready=true
      break
    fi
    echo -n "."
    sleep 2
  done
  echo ""
  if [[ "$local_ready" != "true" ]]; then
    log_error "MicroK8s no quedo ready dentro del timeout"
    exit 1
  fi
else
  log_success "MicroK8s ready"
fi

echo ""

################################################################################
# Step 3: Validar cluster
################################################################################

log_info "Paso 3/6: Validando cluster..."

# Test kubectl
if ! kctl cluster-info &>/dev/null 2>&1; then
  log_error "Cluster no responde"
  exit 1
fi

log_success "Cluster operativo"

# Ver nodes
log_info "Nodos en cluster:"
kctl get nodes || true

echo ""

################################################################################
# Step 4: Verificar namespaces
################################################################################

log_info "Paso 4/6: Verificando namespace base..."

# Verificar que namespace realistic existe
if ! kctl get namespace realistic &>/dev/null 2>&1; then
  log_warn "Namespace 'realistic' no existe, recreando..."
  kctl create namespace realistic
fi

log_success "Namespace 'realistic' disponible"

# Ver status de servicios
log_info "Servicios en namespace 'realistic':"
kctl get svc -n realistic 2>/dev/null || log_warn "Sin servicios aun"

echo ""

################################################################################
# Step 5: Levantar escenario seleccionado
################################################################################

log_info "Paso 5/6: Ejecutando setup de escenario (${SCENARIO})..."
confirm_startup_plan
run_scenario_setup

echo ""

################################################################################
# Step 6: Información final
################################################################################

log_info "Paso 6/6: Resumen final..."

cat << EOF

${GREEN}✓ STARTUP COMPLETADO${NC}

Escenario activo: ${SCENARIO}

Estado del Cluster:
  • MicroK8s: $(microk8s status 2>/dev/null | grep -i microk8s | head -1 || echo 'OK')
  • Namespaces: $(kctl get ns --no-headers 2>/dev/null | wc -l) encontrados
  • Nodos: $(kctl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w) ready

Servicios:
EOF

case "$SCENARIO" in
  s2) ACTIVE_NS="mubench-real" ;;
  s3) ACTIVE_NS="mubench-advanced" ;;
  s4) ACTIVE_NS="mubench-s4" ;;
esac

if kctl get pods -n "$ACTIVE_NS" &>/dev/null 2>&1; then
  echo "  • Pods en '$ACTIVE_NS': $(kctl get pods -n "$ACTIVE_NS" --no-headers 2>/dev/null | wc -l)"
  
  # Mostrar si hay pods stuck
  stuck_pods=$(kctl get pods -n "$ACTIVE_NS" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
  if [ "$stuck_pods" -gt 0 ]; then
    echo -e "  ${YELLOW}! Pods en estado no-Running: $stuck_pods${NC}"
  fi
else
  echo "  • Sin pods visibles en '$ACTIVE_NS'"
fi

cat << EOF

Próximos pasos:

  1. Para campaña reproducible S2:
    bash scripts/run-s2-final-repro.sh --execute --continue-on-readiness-fail

  2. Para campaña integrada S6:
    bash scripts/run-s6-integrated-repro.sh --execute --continue-on-readiness-fail

  3. Para test individual:
     bash scripts/run-k6-benchmark.sh --control C1 --variant baseline --vus 1

  4. Para monitoreo en tiempo real:
     watch kubectl top pods -n realistic

Dashboards disponibles:
  • Prometheus: http://localhost:30000
  • Grafana:    http://localhost:30030

${YELLOW}Nota:${NC} Puedes reiniciar con ultimo escenario usando: --scenario last

EOF

log_success "¡Sistema listo para experimentar!"
echo ""
