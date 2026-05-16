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
PROFILE_FILE="${ROOT_DIR}/scripts/s2-final-profile.env"
RESULTS_DIR="${ROOT_DIR}/Testing/results/scaling_tests"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"
EXPERIMENTS_FILTER="${1:-all}"
VARIANT_FILTER="${2:-all}"
TARGET_ENV="${TARGET_ENV:-default}"
SCENARIO_NAMESPACE="${SCENARIO_NAMESPACE:-$([ "$TARGET_ENV" = "postgres-real" ] && echo "mubench-real" || echo "realistic")}"

if [[ -f "$PROFILE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
fi

S2_C4_MODERATE_RPM="${S2_C4_MODERATE_RPM:-1200}"
S2_C4_STRICT_RPM="${S2_C4_STRICT_RPM:-300}"

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
ERROR_THRESHOLD_PERCENT=5     # errores máximos aceptables salvo variantes con rate limiting intencional

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

is_expected_error_variant() {
  local control="$1"
  local variant="$2"

  case "$control/$variant" in
    C4/moderate|C4/strict)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

ensure_tls_secret() {
  local source_ns="$1"
  local secret_name="$2"
  local target_ns="$3"

  if kctl get secret "$secret_name" -n "$target_ns" >/dev/null 2>&1; then
    return 0
  fi

  kctl get secret "$secret_name" -n "$source_ns" -o json | python3 -c '
import json,sys
obj=json.load(sys.stdin)
obj["metadata"]={"name":obj["metadata"]["name"],"namespace":"'"$target_ns"'"}
print(json.dumps(obj))
' | kctl apply -f - >/dev/null
}

get_node_resources() {
  # Retorna: "cpu_millicores memory_mb"
  kctl top nodes 2>/dev/null | tail -1 | awk '{
    cpu_str=$2
    mem_str=$4
    gsub(/m$/, "", cpu_str)
    gsub(/Mi$/, "", mem_str)
    print cpu_str " " mem_str
  }' || echo "0 0"
}

get_namespace_resources() {
  local ns="$1"
  # Retorna: "cpu_millicores memory_mb"
  kctl top pods -n "$ns" 2>/dev/null | tail -n +2 | awk '{
    cpu_m+=$(NF-1); mem_m+=$(NF)
  } END {
    gsub(/m$/, "", cpu_m); gsub(/Mi$/, "", mem_m)
    print (cpu_m+0) " " (mem_m+0)
  }' || echo "0 0"
}

get_k6_metrics() {
  local json_file="$1"
  local duration_s="${2:-60}"
  
  if [ ! -f "$json_file" ]; then
    echo "0 0 0 0"
    return
  fi
  
  # k6 produce JSON Lines (un objeto por línea, no hay objeto resumen)
  # Calcular avg_ms, p95_ms, err_% y rps desde los Points individuales
  python3 << PYEOF
import json
from datetime import datetime
try:
  durations = []
  failed_reqs = 0
  total_reqs = 0
  req_count = 0
  req_times = []
  duration_s = float('$duration_s')

  with open('$json_file') as f:
    for line in f:
      try:
        obj = json.loads(line)
        if obj.get('type') != 'Point':
          continue
        metric = obj.get('metric', '')
        value = obj.get('data', {}).get('value', 0)
        time_s = obj.get('data', {}).get('time', '')

        if metric == 'http_req_duration':
          durations.append(value)  # valor en ms

        elif metric == 'http_req_failed':
          total_reqs += 1
          failed_reqs += int(value)  # value es 1.0 o 0.0

        elif metric == 'http_reqs':
          # En k6, http_reqs suele reportar value=1 por request
          req_count += int(value)
          if time_s:
            try:
              req_times.append(datetime.fromisoformat(time_s))
            except:
              pass

      except: pass

  error_rate = (failed_reqs / total_reqs * 100) if total_reqs > 0 else 0

  avg_ms = (sum(durations) / len(durations)) if durations else 0

  if durations:
    durations.sort()
    idx = int(len(durations) * 0.95)
    p95 = durations[min(idx, len(durations)-1)]
  else:
    p95 = 0

  if duration_s > 0:
    rps = req_count / duration_s
  elif len(req_times) >= 2:
    elapsed = (max(req_times) - min(req_times)).total_seconds()
    rps = (req_count / elapsed) if elapsed > 0 else 0
  else:
    rps = 0

  print(f"{avg_ms:.2f} {p95:.2f} {error_rate:.2f} {rps:.2f}")
except Exception as e:
  print(f"0 0 0 0")
PYEOF
}

run_scaling_test_for_control() {
  local control="$1"
  local variant="$2"
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Control: $control / Variante: $variant"
  log_info "═══════════════════════════════════════════════════════════"
  
  # Obtener baseline (1 VU) de resultados existentes o ejecutar
  # Aplicar control state antes del baseline (reset + variante correcta)
  log_info "Aplicando estado de control para $control/$variant..."
  apply_control_state "$control" "$variant"

  # Siempre ejecutar baseline fresco (no reusar archivos anteriores contaminados)
  local baseline_file="$RESULTS_DIR/scaling_${control}_${variant}_1vus_$(date +%s).json"
  log_info "Ejecutando benchmark baseline (1 VU)..."

  local baseline_k6_exit=0
  bash "$ROOT_DIR/scripts/run-k6-benchmark.sh" \
    --control "$control" \
    --variant "$variant" \
    --target-env "$TARGET_ENV" \
    --vus 1 \
    --duration 60 \
    --output "$baseline_file" || baseline_k6_exit=$?

  if [ "$baseline_k6_exit" -ne 0 ]; then
    log_warn "k6 baseline terminó con exit code $baseline_k6_exit (se analizará JSON igualmente)"
  fi

  if [ ! -f "$baseline_file" ]; then
    log_error "No se generó JSON baseline para $control/$variant"
    return 1
  fi
  
  local baseline_avg baseline_p95 baseline_err baseline_rps
  read -r baseline_avg baseline_p95 baseline_err baseline_rps < <(get_k6_metrics "$baseline_file" 60)

  local baseline_cpu baseline_mem
  read -r baseline_cpu baseline_mem < <(get_node_resources)
  baseline_cpu="${baseline_cpu//[^0-9]/}"
  baseline_mem="${baseline_mem//[^0-9]/}"
  baseline_cpu="${baseline_cpu:-0}"
  baseline_mem="${baseline_mem:-0}"
  local node_cpu_max=6000  # 6 cores en mC (asumiendo 6 cores)
  local node_mem_max=12000 # 12GB en MB (asumiendo 12GB)
  local baseline_cpu_percent=$((baseline_cpu * 100 / node_cpu_max))
  local baseline_mem_percent=$((baseline_mem * 100 / node_mem_max))

  # Guardar baseline en CSV (VU=1)
  echo "$control,$variant,1,$baseline_avg,$baseline_p95,$baseline_err,$baseline_rps,$baseline_cpu,$baseline_mem" >> "$REPORT_CSV"
  
  log_success "Baseline (1 VU): avg=${baseline_avg}ms, p95=${baseline_p95}ms, err=${baseline_err}%, rps=${baseline_rps}"
  
  local continue_scaling=true
  
  # Test progresivo
  for vus in 5 10 20; do
    if [ "$continue_scaling" = false ]; then
      log_warn "Escalamiento detenido para $control/$variant"
      break
    fi
    
    log_info "\n🔄 Testando con $vus VUs..."
    
    local test_file="$RESULTS_DIR/scaling_${control}_${variant}_${vus}vus_$(date +%s).json"
    
    # Reaplicar control state antes de cada nivel de VUs
    apply_control_state "$control" "$variant"

    # Ejecutar k6
    local k6_exit=0
    bash "$ROOT_DIR/scripts/run-k6-benchmark.sh" \
      --control "$control" \
      --variant "$variant" \
      --target-env "$TARGET_ENV" \
      --vus "$vus" \
      --duration "$DURATION_PER_STAGE" \
      --output "$test_file" || k6_exit=$?

    if [ "$k6_exit" -ne 0 ]; then
      log_warn "k6 con $vus VUs terminó con exit code $k6_exit (se analizará JSON igualmente)"
    fi

    if [ ! -f "$test_file" ]; then
      log_error "No se generó JSON para $control/$variant con $vus VUs"
      continue_scaling=false
      break
    fi
    
    # Analizar resultados
    local avg_ms p95 errors rps
    read -r avg_ms p95 errors rps < <(get_k6_metrics "$test_file" "$DURATION_PER_STAGE")
    
    log_success "Resultados con $vus VUs:"
    echo -e "  ${BLUE}avg:${NC} ${avg_ms}ms (baseline: ${baseline_avg}ms)"
    echo -e "  ${BLUE}p95:${NC} ${p95}ms (baseline: ${baseline_p95}ms)"
    echo -e "  ${BLUE}Errors:${NC} ${errors}% (baseline: ${baseline_err}%)"
    echo -e "  ${BLUE}RPS:${NC} ${rps} (baseline: ${baseline_rps})"
    
    # Evaluar thresholds
    local node_cpu node_mem
    read -r node_cpu node_mem < <(get_node_resources)
    node_cpu="${node_cpu//[^0-9]/}"
    node_mem="${node_mem//[^0-9]/}"
    node_cpu="${node_cpu:-0}"
    node_mem="${node_mem:-0}"
    
    local cpu_percent=$((node_cpu * 100 / node_cpu_max))
    local mem_percent=$((node_mem * 100 / node_mem_max))
    local expected_error_variant=false
    if is_expected_error_variant "$control" "$variant"; then
      expected_error_variant=true
    fi
    
    echo -e "  ${BLUE}Recursos nodo:${NC} CPU=$cpu_percent%, MEM=$mem_percent%"

    if (( $(echo "$errors > $ERROR_THRESHOLD_PERCENT" | bc -l) )); then
      if [ "$expected_error_variant" = true ]; then
        log_warn "Error rate ($errors%) esperado para $control/$variant por rate limiting"
      else
        log_warn "Error rate ($errors%) supera threshold ($ERROR_THRESHOLD_PERCENT%) → DETENER"
        continue_scaling=false
      fi
    fi
    
    # Guardar resultado en CSV
    echo "$control,$variant,$vus,$avg_ms,$p95,$errors,$rps,$node_cpu,$node_mem" >> "$REPORT_CSV"

    # Decisión de continuar
    if [ "$continue_scaling" = false ]; then
      :
    elif (( $(echo "$p95 > $P95_THRESHOLD_MS" | bc -l) )); then
      log_warn "p95 ($p95ms) supera threshold ($P95_THRESHOLD_MS ms) → DETENER"
      continue_scaling=false
    elif [ "$cpu_percent" -gt "$CPU_THRESHOLD_PERCENT" ]; then
      log_warn "CPU ($cpu_percent%) supera threshold ($CPU_THRESHOLD_PERCENT%) → DETENER"
      continue_scaling=false
    elif [ "$mem_percent" -gt "$MEMORY_THRESHOLD_PERCENT" ]; then
      log_warn "Memoria ($mem_percent%) supera threshold ($MEMORY_THRESHOLD_PERCENT%) → DETENER"
      continue_scaling=false
    elif [ "$expected_error_variant" = false ] && (( $(echo "$errors > $ERROR_THRESHOLD_PERCENT" | bc -l) )); then
      log_warn "Error rate ($errors%) supera threshold ($ERROR_THRESHOLD_PERCENT%) → DETENER"
      continue_scaling=false
    else
      if [ "$expected_error_variant" = true ] && (( $(echo "$errors > $ERROR_THRESHOLD_PERCENT" | bc -l) )); then
        log_success "✓ Métricas OK, con errores esperados por rate limiting"
      else
        log_success "✓ Métricas OK, escalamiento viable"
      fi
    fi
  done
}

################################################################################
# Función: Aplicar estado del control (reset + variante)
################################################################################

apply_control_state() {
  local control="$1"
  local variant="$2"
  local NS="$SCENARIO_NAMESPACE"

  log_info "  → Reseteando estado previo..."

  # Limpiar recursos de red/ingress/istio
  kctl delete ingress --all -n "$NS" --ignore-not-found &>/dev/null || true
  kctl delete gateway.networking.istio.io --all -n "$NS" --ignore-not-found &>/dev/null || true
  kctl delete virtualservice --all -n "$NS" --ignore-not-found &>/dev/null || true
  kctl delete networkpolicy --all -n "$NS" --ignore-not-found &>/dev/null || true

  # Resetear rate limit a neutral
  kctl set env deployment/api-service -n "$NS" \
    RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 &>/dev/null || true

  # Resetar label istio-injection
  kctl label namespace "$NS" istio-injection=disabled --overwrite &>/dev/null || true

  if [ "$TARGET_ENV" = "postgres-real" ]; then
    kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" &>/dev/null || true
  fi

  log_info "  → Aplicando variante $control/$variant..."

  case "$control" in
    C1)
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        ensure_tls_secret realistic mubench-tls "$NS"
        ensure_tls_secret realistic realistic-tls "$NS"
        case "$variant" in
          baseline) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway-real.yaml" &>/dev/null ;;
          istio)    kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-istio-real.yaml" &>/dev/null ;;
          kong)     kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-kong-real.yaml" &>/dev/null ;;
        esac
      else
        case "$variant" in
          baseline) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway.yaml" &>/dev/null ;;
          istio)    kctl apply -f "$ROOT_DIR/experiments/01-api-gateway-realistic/istio/01-services-istio.yaml" &>/dev/null ;;
          kong)     kctl apply -f "$ROOT_DIR/experiments/01-api-gateway-realistic/kong/01-services-kong.yaml" &>/dev/null ;;
        esac
      fi
      ;;
    C2)
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        case "$variant" in
          baseline) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" &>/dev/null ;;
          istio-mtls) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-istio-mtls-real.yaml" &>/dev/null ;;
          linkerd-mtls) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-linkerd-mtls-real.yaml" &>/dev/null ;;
        esac
      else
        local manifest_dir="$ROOT_DIR/experiments/02-mtls-service-mesh-realistic/$variant"
        if [ -d "$manifest_dir" ]; then
          for f in "$manifest_dir"/*.yaml; do
            [ -f "$f" ] && kctl apply -f "$f" &>/dev/null || true
          done
        fi
      fi
      ;;
    C3)
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        case "$variant" in
          basic)  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-real.yaml" &>/dev/null ;;
          strict) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml" &>/dev/null ;;
        esac
      else
        case "$variant" in
          basic)  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy.yaml" &>/dev/null ;;
          strict) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-strict.yaml" &>/dev/null ;;
        esac
      fi
      ;;
    C4)
      case "$variant" in
        moderate)
          kctl set env deployment/api-service -n "$NS" \
            RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM="$S2_C4_MODERATE_RPM" &>/dev/null
          kctl rollout restart deployment/api-service -n "$NS" &>/dev/null
          ;;
        strict)
          kctl set env deployment/api-service -n "$NS" \
            RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM="$S2_C4_STRICT_RPM" &>/dev/null
          kctl rollout restart deployment/api-service -n "$NS" &>/dev/null
          ;;
      esac
      ;;
  esac

  # Esperar rollout de los servicios principales
  for dep in auth-service api-service data-service; do
    kctl rollout status deployment/"$dep" -n "$NS" --timeout=120s &>/dev/null || true
  done

  sleep 3  # Breve pausa para estabilizar
}

################################################################################
# Main
################################################################################

# Encabezado del report CSV
REPORT_CSV="$RESULTS_DIR/scaling-report_${TARGET_ENV}_$(date +%Y%m%d).csv"
echo "control,variant,vus,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib" > "$REPORT_CSV"

log_info "Iniciando test de escalabilidad progresiva"
log_info "Resultados: $RESULTS_DIR"
log_info "Entorno objetivo: $TARGET_ENV (namespace: $SCENARIO_NAMESPACE)"
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
