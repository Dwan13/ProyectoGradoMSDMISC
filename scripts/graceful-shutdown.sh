#!/usr/bin/env bash
set -euo pipefail

################################################################################
# graceful-shutdown.sh
#
# Script para apagar la máquina gracefully
# - Para servicios Kubernetes
# - Limpia recursos
# - Detiene MicroK8s
# - Prepara máquina para apagado
#
# Uso: bash scripts/graceful-shutdown.sh
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

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

################################################################################
# Step 1: Detener tests en ejecución (si los hay)
################################################################################

log_info "Paso 1/5: Verificando procesos en ejecución..."

if pgrep -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls" > /dev/null; then
  log_warn "Hay scripts de test en ejecución"
  log_info "Esperando a que terminen (máx 60s)..."
  
  sleep 5
  
  if pgrep -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls" > /dev/null; then
    log_warn "Tests aún en ejecución, terminando..."
    pkill -f "run-k6-benchmark.sh\|run-scaling-tests.sh\|run-all-controls" || true
    sleep 2
  fi
fi

log_success "Procesos limpios"
echo ""

################################################################################
# Step 2: Eliminar recursos Kubernetes
################################################################################

log_info "Paso 2/5: Limpiando recursos Kubernetes..."

# Delete all pods in realistic namespace
if microk8s kubectl get namespace realistic &>/dev/null 2>&1; then
  log_info "  → Eliminando pods en namespace 'realistic'..."
  microk8s kubectl delete pods -n realistic --all --ignore-not-found \
    --grace-period=30 2>/dev/null || true
  sleep 2
fi

log_success "Recursos Kubernetes limpiados"
echo ""

################################################################################
# Step 3: Detener servicios críticos
################################################################################

log_info "Paso 3/5: Deteniendo servicios..."

# Stop key deployments gracefully
if microk8s kubectl get deployment -n realistic &>/dev/null 2>&1; then
  log_info "  → Escalando deployments a 0 replicas..."
  microk8s kubectl scale deployment --all -n realistic --replicas=0 \
    2>/dev/null || true
fi

log_success "Servicios detenidos"
echo ""

################################################################################
# Step 4: Detener MicroK8s
################################################################################

log_info "Paso 4/5: Deteniendo MicroK8s..."

if microk8s status &>/dev/null 2>&1; then
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
  • Pods Kubernetes: Eliminados
  • Servicios: Detenidos
  • MicroK8s: Parado

Recursos limpios:
  • Data en volúmenes: PRESERVADO (para mañana)
  • Configuración: PRESERVADA
  • Estado: LIMPIO

Próximos pasos:
  1. Ahora puedes apagar la máquina sin problema
  2. Mañana al encender, ejecuta: bash scripts/graceful-startup.sh
  3. Luego ejecuta tests normalmente

${YELLOW}Nota:${NC} Todos tus datos y configuración se preservaron.

EOF

log_success "¡Listo! Máquina segura para apagar"
