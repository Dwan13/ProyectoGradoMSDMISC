#!/usr/bin/env bash
set -euo pipefail

################################################################################
# graceful-startup.sh
#
# Script para levantar la máquina después del apagado
# - Levanta MicroK8s
# - Verifica cluster status
# - Valida servicios
# - Prepara para tests
#
# Uso: bash scripts/graceful-startup.sh
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

banner() {
  echo ""
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║${NC}        GRACEFUL STARTUP - µBench Project             ${YELLOW}║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

banner

################################################################################
# Step 1: Verificar MicroK8s instalado
################################################################################

log_info "Paso 1/5: Verificando MicroK8s..."

if ! command -v microk8s &> /dev/null; then
  log_error "MicroK8s no está instalado"
  log_info "Ejecuta: bash scripts/full-project-setup.sh"
  exit 1
fi

log_success "MicroK8s encontrado"
echo ""

################################################################################
# Step 2: Levantar MicroK8s
################################################################################

log_info "Paso 2/5: Levantando MicroK8s..."

microk8s start || log_warn "MicroK8s podría estar en recuperación..."

log_info "Esperando a que MicroK8s esté ready (máx 60s)..."

if ! microk8s status --wait-ready --timeout=300 &>/dev/null 2>&1; then
  log_warn "MicroK8s tardando, probando manualmente..."
  for i in {1..30}; do
    if microk8s status &>/dev/null 2>&1; then
      log_success "MicroK8s está ready"
      break
    fi
    echo -n "."
    sleep 2
  done
  echo ""
else
  log_success "MicroK8s ready"
fi

echo ""

################################################################################
# Step 3: Validar cluster
################################################################################

log_info "Paso 3/5: Validando cluster..."

# Test kubectl
if ! microk8s kubectl cluster-info &>/dev/null 2>&1; then
  log_error "Cluster no responde"
  exit 1
fi

log_success "Cluster operativo"

# Ver nodes
log_info "Nodos en cluster:"
microk8s kubectl get nodes || true

echo ""

################################################################################
# Step 4: Verificar namespaces
################################################################################

log_info "Paso 4/5: Verificando namespaces..."

# Verificar que namespace realistic existe
if ! microk8s kubectl get namespace realistic &>/dev/null 2>&1; then
  log_warn "Namespace 'realistic' no existe, recreando..."
  microk8s kubectl create namespace realistic
fi

log_success "Namespace 'realistic' disponible"

# Ver status de servicios
log_info "Servicios en namespace 'realistic':"
microk8s kubectl get svc -n realistic 2>/dev/null || log_warn "Sin servicios aún"

echo ""

################################################################################
# Step 5: Re-escalar deployments
################################################################################

log_info "Paso 5/6: Levantando servicios realistas..."

if microk8s kubectl get deployment -n realistic &>/dev/null 2>&1; then
  DEPS=$(microk8s kubectl get deployment -n realistic --no-headers 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
  if [ -n "$DEPS" ]; then
    log_info "  → Escalando deployments a 1 réplica: $DEPS"
    microk8s kubectl scale deployment $DEPS -n realistic --replicas=1 2>/dev/null || true

    log_info "  → Esperando que los pods estén ready..."
    for dep in $DEPS; do
      microk8s kubectl rollout status deployment/"$dep" -n realistic --timeout=120s 2>/dev/null \
        && log_success "  ✓ $dep ready" || log_warn "  ! $dep tardó más de lo esperado"
    done
  else
    log_warn "No hay deployments. Ejecuta el primer test y se desplegarán automáticamente."
  fi
else
  log_warn "No hay deployments en namespace 'realistic'. Ejecuta run-all-controls-experiments.sh."
fi

echo ""

################################################################################
# Step 6: Información final
################################################################################

log_info "Paso 6/6: Resumen final..."

cat << EOF

${GREEN}✓ STARTUP COMPLETADO${NC}

Estado del Cluster:
  • MicroK8s: $(microk8s status 2>/dev/null | grep -i microk8s | head -1 || echo 'OK')
  • Namespaces: $(microk8s kubectl get ns --no-headers 2>/dev/null | wc -l) encontrados
  • Nodos: $(microk8s kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w) ready

Servicios Realistas:
EOF

if microk8s kubectl get pods -n realistic &>/dev/null 2>&1; then
  echo "  • Pods en 'realistic': $(microk8s kubectl get pods -n realistic --no-headers 2>/dev/null | wc -l)"
  
  # Mostrar si hay pods stuck
  stuck_pods=$(microk8s kubectl get pods -n realistic --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
  if [ "$stuck_pods" -gt 0 ]; then
    echo -e "  ${YELLOW}! Pods en estado no-Running: $stuck_pods${NC}"
  fi
else
  echo "  • No hay pods aún (espera a que se desplieguen en primer test)"
fi

cat << EOF

Próximos pasos:

  1. Para ejecutar tests completos (1 VU × 12 escenarios):
     bash scripts/run-all-controls-experiments.sh

  2. Para tests de escalabilidad (1→5→10→20 VUs):
     bash scripts/run-scaling-tests.sh

  3. Para test individual:
     bash scripts/run-k6-benchmark.sh --control C1 --variant baseline --vus 1

  4. Para monitoreo en tiempo real:
     watch kubectl top pods -n realistic

Dashboards disponibles:
  • Prometheus: http://localhost:30000
  • Grafana:    http://localhost:30001 (admin/prom-operator)

${YELLOW}Nota:${NC} Los pods se desplegarán cuando ejecutes el primer test.

EOF

log_success "¡Sistema listo para experimentar!"
echo ""
