#!/bin/bash
# ================================================================
# MuBench Quick Validation Script
# Verifica que todos los componentes estén correctamente instalados
# ================================================================

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

SUCCESS=0
WARNINGS=0
ERRORS=0

log() { echo -e "${CYAN}[CHECK]${RESET} $*"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; SUCCESS=$((SUCCESS+1)); }
warn() { echo -e "${YELLOW}⚠️ $*${RESET}"; WARNINGS=$((WARNINGS+1)); }
error() { echo -e "${RED}❌ $*${RESET}"; ERRORS=$((ERRORS+1)); }

echo "================================================================"
echo " MuBench Environment Validation"
echo "================================================================"
echo ""

# Check MicroK8s
log "Verificando MicroK8s..."
if command -v microk8s >/dev/null 2>&1; then
    if microk8s status --wait-ready >/dev/null 2>&1; then
        success "MicroK8s está instalado y corriendo"
    else
        error "MicroK8s instalado pero no está corriendo"
    fi
else
    error "MicroK8s no está instalado"
fi

# Check k6
log "Verificando k6..."
if command -v k6 >/dev/null 2>&1; then
    VERSION=$(k6 version | head -n1)
    success "k6 instalado: $VERSION"
else
    warn "k6 no está instalado. Ejecutar: ./scripts/install_k6.sh"
fi

# Check Python
log "Verificando Python 3..."
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version)
    success "Python instalado: $PYTHON_VERSION"
else
    error "Python 3 no está instalado"
fi

# Check jq (for JSON parsing)
log "Verificando jq (JSON parser)..."
if command -v jq >/dev/null 2>&1; then
    success "jq instalado"
else
    warn "jq no instalado (recomendado para análisis JSON)"
fi

# Check Prometheus
log "Verificando Prometheus..."
if microk8s kubectl get pods -n observability 2>/dev/null | grep -q prometheus; then
    success "Prometheus pods encontrados en namespace observability"
else
    warn "Prometheus no encontrado en namespace observability"
fi

# Check Grafana
log "Verificando Grafana..."
if microk8s kubectl get pods -n observability 2>/dev/null | grep -q grafana; then
    success "Grafana pods encontrados"
else
    warn "Grafana no encontrado"
fi

# Check mubench-realistic pods
log "Verificando pods de mubench-realistic..."
POD_COUNT=$(microk8s kubectl get pods -n mubench-realistic 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$POD_COUNT" -gt 0 ]]; then
    success "mubench-realistic pods Running: $POD_COUNT"
else
    warn "No se encontraron pods en mubench-realistic. Ejecutar: ./scripts/deploy-mubench-complete.sh"
fi

# Check realistic pods
log "Verificando pods de realistic..."
REAL_COUNT=$(microk8s kubectl get pods -n realistic 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$REAL_COUNT" -ge 4 ]]; then
    success "realistic pods Running: $REAL_COUNT"
else
    warn "Pods realistic incompletos ($REAL_COUNT/4). Ejecutar: ./scripts/deploy-mubench-complete.sh"
fi

# Check scripts
log "Verificando scripts..."
if [[ -x "./scripts/deploy-mubench-complete.sh" ]]; then
    success "deploy-mubench-complete.sh es ejecutable"
else
    error "deploy-mubench-complete.sh no es ejecutable o no existe"
fi

if [[ -x "./scripts/install_k6.sh" ]]; then
    success "install_k6.sh es ejecutable"
else
    warn "install_k6.sh no es ejecutable"
fi

# Check k6 test files
log "Verificando scripts de k6 (experimentos realistic)..."
if [[ -f "./RealisticServices/k6/realistic-flow.js" ]]; then
    success "realistic-flow.js existe"
else
    warn "realistic-flow.js no encontrado en RealisticServices/k6/"
fi

# Check experimentos
log "Verificando directorios de experimentos..."
for exp in 01-api-gateway-realistic 02-mtls-service-mesh-realistic 03-network-policies-realistic 04-rate-limiting-realistic; do
    if [[ -d "./experiments/${exp}" ]]; then
        success "experiments/${exp} existe"
    else
        warn "experiments/${exp} no encontrado"
    fi
done

# Check ServiceCell
log "Verificando ServiceCell mejorado..."
if [[ -f "./ServiceCell/CellController-enhanced.py" ]]; then
    success "CellController-enhanced.py existe"
else
    error "CellController-enhanced.py no encontrado"
fi

# Check templates
log "Verificando templates de K8s..."
if [[ -f "./Deployers/K8sDeployer/Templates/DeploymentTemplate.yaml" ]]; then
    if grep -q "COMM_PROTOCOL" "./Deployers/K8sDeployer/Templates/DeploymentTemplate.yaml"; then
        success "DeploymentTemplate.yaml actualizado con COMM_PROTOCOL"
    else
        warn "DeploymentTemplate.yaml existe pero no tiene COMM_PROTOCOL"
    fi
else
    error "DeploymentTemplate.yaml no encontrado"
fi

# Summary
echo ""
echo "================================================================"
echo " Resumen de Validación"
echo "================================================================"
echo -e "${GREEN}Exitosos:${RESET}    $SUCCESS"
echo -e "${YELLOW}Advertencias:${RESET} $WARNINGS"
echo -e "${RED}Errores:${RESET}      $ERRORS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✅ Sistema listo para usar muBench${RESET}"
    echo ""
    echo "Próximos pasos:"
    echo "  1. Desplegar (si no está): ./scripts/deploy-mubench-complete.sh"
    echo "  2. Ver credenciales: cat ~/.mubench_access"
    echo "  3. Acceder Grafana: http://localhost:30001/login"
    echo "  4. Ejecutar experimento: cd experiments/01-api-gateway-realistic && bash run-exp01-realistic.sh"
    exit 0
else
    echo -e "${RED}❌ Se encontraron errores. Revisar y corregir.${RESET}"
    exit 1
fi
