#!/usr/bin/env bash
set -euo pipefail

################################################################################
# run-scaling-tests.sh
# 
# Script para test progresivo de escalabilidad: 1 VU → 5 VU → 10 VU → 20 VU
# Monitorea CPU/memoria en cada etapa y recomienda si continuar o detener
#
# Uso: bash scripts/run-scaling-tests.sh [control_filter] [variant_filter]
# Ejemplo: bash scripts/run-scaling-tests.sh "C2" "istio-mtls"
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/Testing/results/scaling_tests"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"
EXPERIMENTS_FILTER="${1:-all}"
VARIANT_FILTER="${2:-all}"

mkdir -p "$RESULTS_DIR"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
VUSER_STAGES=(1 5 10 20)
DURATION_PER_STAGE=60
CHECK_INTERVAL=5  # segundos entre mediciones de recursos

# Umbrales (si se superan, detener escalamiento)
CPU_THRESHOLD_PERCENT=70      # % del nodo
MEMORY_THRESHOLD_PERCENT=80   # % del nodo
P95_THRESHOLD_MS=500          # latencia p95 máxima aceptable

# Controles predefinidos (por defecto todos)
declare -a CONTROLS=(
  "C1_baseline"
  "C1_istio"
  "C1_kong"
  "C2_baseline"
  "C2_istio-mtls"
  "C2_linkerd-mtls"
  "C3_baseline"
  "C3_basic"
  "C3_strict"
  "C4_baseline"
  "C4_moderate"
  "C4_strict"
)

################################################################################
# Funciones auxiliares
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*"
}

get_node_resources() {
  # Retorna: "cpu_millicores memory_mb"
  kubectl top nodes 2>/dev/null | tail -1 | awk '{
    cpu_str=$2
    mem_str=$3
    gsub(/m$/, "", cpu_str)
    gsub(/Mi$/, "", mem_str)
    print cpu_str " " mem_str
  }' || echo "0 0"
}

get_namespace_resources() {
  local ns="$1"
  # Retorna: "cpu_millicores memory_mb"
  kubectl top pods -n "$ns" 2>/dev/null | tail -n +2 | awk '{
    cpu_m+=$(NF-1); mem_m+=$(NF)
  } END {
    gsub(/m$/, "", cpu_m); gsub(/Mi$/, "", mem_m)
    print (cpu_m+0) " " (mem_m+0)
  }' || echo "0 0"
}

get_k6_metrics() {
  local json_file="$1"
  
  if [ ! -f "$json_file" ]; then
    echo "0 0 0"
    return
  fi
  
  # Extraer metrics finales (último objeto de salida k6)
  local checks=0
  local p95=0
  local errors=0
  
  # k6 JSON Lines: parsear último objeto con type:summary
  python3 << PYEOF
import json, sys
try:
  with open('$json_file') as f:
    lines = f.readlines()
  
  checks_val = 100
  p95_val = 0
  error_val = 0
  
  # Buscar check rate
  for line in reversed(lines):
    try:
      obj = json.loads(line)
      if obj.get('metric') == 'checks' and obj.get('type') == 'Point':
        checks_val = obj.get('data', {}).get('value', 1) * 100
        break
    except: pass
  
  # Buscar p95
  for line in reversed(lines):
    try:
      obj = json.loads(line)
      if (obj.get('metric') == 'http_req_duration' and 
          obj.get('data', {}).get('tags', {}).get('quantile') == '0.95'):
        p95_val = obj.get('data', {}).get('value', 0) / 1000  # a ms
        break
    except: pass
  
  # Buscar error rate
  for line in reversed(lines):
    try:
      obj = json.loads(line)
      if obj.get('metric') == 'http_req_failed' and obj.get('type') == 'Point':
        error_val = obj.get('data', {}).get('value', 0) * 100
        break
    except: pass
  
  print(f"{checks_val:.1f} {p95_val:.2f} {error_val:.2f}")
except Exception as e:
  print(f"0 0 0")
PYEOF
}

run_scaling_test_for_control() {
  local control="$1"
  local variant="$2"
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Control: $control / Variante: $variant"
  log_info "═══════════════════════════════════════════════════════════"
  
  # Obtener baseline (1 VU) de resultados existentes o ejecutar
  local baseline_file=$(ls -t "$RESULTS_DIR"/scaling_${control}_${variant}_1vus_*.json 2>/dev/null | head -1 || echo "")
  
  if [ -z "$baseline_file" ] || [ ! -f "$baseline_file" ]; then
    log_info "Ejecutando benchmark baseline (1 VU)..."
    baseline_file="$RESULTS_DIR/scaling_${control}_${variant}_1vus_$(date +%s).json"
    
    # Ejecutar k6 baseline
    bash "$ROOT_DIR/scripts/run-k6-benchmark.sh" \
      --control "$control" \
      --variant "$variant" \
      --vus 1 \
      --duration 60 \
      --output "$baseline_file" || {
      log_error "Baseline failed para $control/$variant"
      return 1
    }
  fi
  
  local baseline_checks baseline_p95 baseline_err
  read -r baseline_checks baseline_p95 baseline_err < <(get_k6_metrics "$baseline_file")
  
  log_success "Baseline (1 VU): checks=$baseline_checks%, p95=${baseline_p95}ms, err=$baseline_err%"
  
  local continue_scaling=true
  
  # Test progresivo
  for vus in 5 10 20; do
    if [ "$continue_scaling" = false ]; then
      log_warn "Escalamiento detenido para $control/$variant"
      break
    fi
    
    log_info "\n🔄 Testando con $vus VUs..."
    
    local test_file="$RESULTS_DIR/scaling_${control}_${variant}_${vus}vus_$(date +%s).json"
    
    # Ejecutar k6
    if ! bash "$ROOT_DIR/scripts/run-k6-benchmark.sh" \
      --control "$control" \
      --variant "$variant" \
      --vus "$vus" \
      --duration "$DURATION_PER_STAGE" \
      --output "$test_file"; then
      log_error "Test con $vus VUs falló"
      continue_scaling=false
      break
    fi
    
    # Analizar resultados
    local checks p95 errors
    read -r checks p95 errors < <(get_k6_metrics "$test_file")
    
    log_success "Resultados con $vus VUs:"
    echo -e "  ${BLUE}Checks:${NC} $checks% (baseline: $baseline_checks%)"
    echo -e "  ${BLUE}p95:${NC} ${p95}ms (baseline: ${baseline_p95}ms)"
    echo -e "  ${BLUE}Errors:${NC} $errors% (baseline: $baseline_err%)"
    
    # Evaluar thresholds
    local node_cpu node_mem
    read -r node_cpu node_mem < <(get_node_resources)
    
    local node_cpu_max=6000  # 6 cores en mC (asumiendo 6 cores)
    local node_mem_max=12000 # 12GB en MB (asumiendo 12GB)
    
    local cpu_percent=$((node_cpu * 100 / node_cpu_max))
    local mem_percent=$((node_mem * 100 / node_mem_max))
    
    echo -e "  ${BLUE}Recursos nodo:${NC} CPU=$cpu_percent%, MEM=$mem_percent%"
    
    # Decisión de continuar
    if (( $(echo "$p95 > $P95_THRESHOLD_MS" | bc -l) )); then
      log_warn "p95 ($p95ms) supera threshold ($P95_THRESHOLD_MS ms) → DETENER"
      continue_scaling=false
    elif [ "$cpu_percent" -gt "$CPU_THRESHOLD_PERCENT" ]; then
      log_warn "CPU ($cpu_percent%) supera threshold ($CPU_THRESHOLD_PERCENT%) → DETENER"
      continue_scaling=false
    elif [ "$mem_percent" -gt "$MEMORY_THRESHOLD_PERCENT" ]; then
      log_warn "Memoria ($mem_percent%) supera threshold ($MEMORY_THRESHOLD_PERCENT%) → DETENER"
      continue_scaling=false
    else
      log_success "✓ Métricas OK, escalamiento viable"
    fi
    
    # Guardar resultado en CSV
    echo "$control,$variant,$vus,$checks%,$p95,$errors%,$cpu_percent%,$mem_percent%" >> \
      "$RESULTS_DIR/scaling-report_$(date +%Y%m%d).csv"
  done
}

################################################################################
# Main
################################################################################

# Encabezado del report CSV
REPORT_CSV="$RESULTS_DIR/scaling-report_$(date +%Y%m%d).csv"
if [ ! -f "$REPORT_CSV" ]; then
  echo "control,variant,vus,checks,p95_ms,errors,cpu_%,mem_%" > "$REPORT_CSV"
fi

log_info "Iniciando test de escalabilidad progresiva"
log_info "Resultados: $RESULTS_DIR"
log_info "Umbrales: CPU<$CPU_THRESHOLD_PERCENT%, MEM<$MEMORY_THRESHOLD_PERCENT%, p95<${P95_THRESHOLD_MS}ms"

for control_variant in "${CONTROLS[@]}"; do
  IFS='_' read -r control variant <<< "$control_variant"
  
  # Filtros
  if [ "$EXPERIMENTS_FILTER" != "all" ] && [ "$control" != "$EXPERIMENTS_FILTER" ]; then
    continue
  fi
  if [ "$VARIANT_FILTER" != "all" ] && [ "$variant" != "$VARIANT_FILTER" ]; then
    continue
  fi
  
  run_scaling_test_for_control "$control" "$variant" || true
done

log_success "\n✓ Test de escalabilidad completado"
log_info "Reporte: $REPORT_CSV"
echo ""
echo "=== RESUMEN ESCALABILIDAD ==="
cat "$REPORT_CSV"
