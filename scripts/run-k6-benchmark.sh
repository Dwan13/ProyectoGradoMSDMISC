#!/usr/bin/env bash
set -euo pipefail

################################################################################
# run-k6-benchmark.sh
#
# Wrapper unificado para ejecutar k6 benchmarks con configuración óptima
# Automatiza el setup de endpoints, autenticación, TLS y ejecución
#
# Uso: bash scripts/run-k6-benchmark.sh --control C1 --variant istio --vus 5
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"
RESULTS_DIR="${ROOT_DIR}/Testing/results/auto_runs"

# Valores por defecto
CONTROL=""
VARIANT=""
VUS=1
DURATION=60
OUTPUT=""
DRY_RUN=false
HOST_HEADER=""

# Endpoints base (sin controles)
AUTH_BASE_DEFAULT="http://localhost:30084"
API_BASE_DEFAULT="http://localhost:30081"
INSECURE_TLS="true"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

################################################################################
# Parse arguments
################################################################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control) CONTROL="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --vus) VUS="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --host-header) HOST_HEADER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Opción desconocida: $1"; exit 1 ;;
  esac
done

usage() {
  cat << EOF
Uso: $(basename "$0") [opciones]

Opciones:
  --control <C1|C2|C3|C4>        Control a ejecutar (requerido)
  --variant <name>               Variante (baseline, istio, kong, etc.) (requerido)
  --vus <number>                 Virtual users (default: 1)
  --duration <seconds>           Duración del test (default: 60)
  --output <path>                Archivo JSON output (default: auto-generado)
  --host-header <header>         Host header personalizado (opcional)
  --dry-run                       Mostrar configuración sin ejecutar
  -h, --help                      Mostrar esta ayuda

Ejemplos:
  # Test C1 baseline con 5 VUs
  bash scripts/run-k6-benchmark.sh --control C1 --variant baseline --vus 5

  # Test C2 istio-mtls con 10 VUs, salida a archivo específico
  bash scripts/run-k6-benchmark.sh --control C2 --variant istio-mtls --vus 10 \\
    --output Testing/results/custom.json

  # Test C3 strict (network policies) con 1 VU
  bash scripts/run-k6-benchmark.sh --control C3 --variant strict --vus 1
EOF
}

################################################################################
# Validaciones
################################################################################

if [ -z "$CONTROL" ] || [ -z "$VARIANT" ]; then
  log_error "Se requieren --control y --variant"
  usage
  exit 1
fi

if ! command -v k6 &> /dev/null; then
  log_error "k6 no está instalado. Instálalo: https://k6.io/docs/get-started/installation/"
  exit 1
fi

if [ ! -f "$K6_SCRIPT" ]; then
  log_error "Script k6 no encontrado: $K6_SCRIPT"
  exit 1
fi

################################################################################
# Determinar endpoints según control
################################################################################

setup_endpoints() {
  local control="$1"
  local variant="$2"
  
  case "$control" in
    C1)
      case "$variant" in
        baseline)
          AUTH_BASE="https://localhost/auth"
          API_BASE="https://localhost/api"
          HOST_HEADER="localhost"
          INSECURE_TLS="true"
          ;;
        istio)
          AUTH_BASE="https://localhost:30997"
          API_BASE="https://localhost:30997"
          HOST_HEADER="realistic.local"
          INSECURE_TLS="true"
          ;;
        kong)
          AUTH_BASE="https://localhost:30443"
          API_BASE="https://localhost:30443"
          HOST_HEADER="localhost"
          INSECURE_TLS="true"
          ;;
        *)
          log_error "Variante C1 desconocida: $variant"
          return 1
          ;;
      esac
      ;;
    C2)
      # C2 usa HTTP en NodePorts (mTLS es transparente a cliente)
      AUTH_BASE="http://localhost:30084"
      API_BASE="http://localhost:30081"
      HOST_HEADER=""
      INSECURE_TLS="false"
      ;;
    C3)
      # C3 igual a C2 (network policies no cambian endpoints)
      AUTH_BASE="http://localhost:30084"
      API_BASE="http://localhost:30081"
      HOST_HEADER=""
      INSECURE_TLS="false"
      ;;
    C4)
      # C4 igual a C2 (rate limiting no cambia endpoints)
      AUTH_BASE="http://localhost:30084"
      API_BASE="http://localhost:30081"
      HOST_HEADER=""
      INSECURE_TLS="false"
      ;;
    *)
      log_error "Control desconocido: $control"
      return 1
      ;;
  esac
}

################################################################################
# Generar nombre de output si no se especifica
################################################################################

if [ -z "$OUTPUT" ]; then
  mkdir -p "$RESULTS_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  OUTPUT="$RESULTS_DIR/${CONTROL}_${VARIANT}_${VUS}vus_${TIMESTAMP}.json"
fi

################################################################################
# Setup endpoints y validar conexión
################################################################################

log_info "Configurando endpoints para $CONTROL/$VARIANT..."

setup_endpoints "$CONTROL" "$VARIANT" || exit 1

log_info "Validando conectividad..."

# Test de alcanzabilidad básica
if ! timeout 5 curl -k -s -o /dev/null "$AUTH_BASE/login" 2>/dev/null; then
  log_warn "⚠️  No se alcanza $AUTH_BASE - continuando de todas formas"
fi

################################################################################
# Mostrar configuración
################################################################################

cat << EOF

╔════════════════════════════════════════════════════════════════════════╗
║                    CONFIGURACIÓN K6 BENCHMARK                         ║
╚════════════════════════════════════════════════════════════════════════╝

Control:          $CONTROL
Variante:         $VARIANT
VUs:              $VUS
Duración:         ${DURATION}s
Auth Endpoint:    $AUTH_BASE
API Endpoint:     $API_BASE
Host Header:      ${HOST_HEADER:-"(none)"}
TLS Insecure:     $INSECURE_TLS
Output JSON:      $OUTPUT

╔════════════════════════════════════════════════════════════════════════╗

EOF

if [ "$DRY_RUN" = true ]; then
  log_success "Dry-run completado. Para ejecutar, remove --dry-run"
  exit 0
fi

################################################################################
# Ejecutar K6
################################################################################

log_info "Iniciando k6 benchmark..."
echo ""

set +e
k6 run \
  -e AUTH_BASE="$AUTH_BASE" \
  -e API_BASE="$API_BASE" \
  -e K6_INSECURE_SKIP_TLS_VERIFY="$INSECURE_TLS" \
  -e HOST_HEADER="$HOST_HEADER" \
  --vus "$VUS" \
  --duration "${DURATION}s" \
  --out json="$OUTPUT" \
  "$K6_SCRIPT"

K6_EXIT=$?
set -e

################################################################################
# Procesar resultados
################################################################################

if [ "$K6_EXIT" -eq 0 ]; then
  log_success "k6 ejecutado exitosamente"
else
  log_warn "k6 finalizó con código $K6_EXIT (puede haber threshold failures)"
fi

# Extraer métricas finales
log_info "Extrayendo métricas..."

python3 << PYEOF 2>/dev/null || true
import json, sys

try:
  with open('$OUTPUT') as f:
    lines = f.readlines()
  
  # Buscar summary final
  checks_rate = 100
  p95_latency = 0
  error_rate = 0
  total_reqs = 0
  
  for line in reversed(lines):
    try:
      obj = json.loads(line)
      
      if obj.get('metric') == 'checks' and obj.get('type') == 'Point':
        checks_rate = obj.get('data', {}).get('value', 1) * 100
      elif (obj.get('metric') == 'http_req_duration' and 
            obj.get('data', {}).get('tags', {}).get('quantile') == '0.95'):
        p95_latency = obj.get('data', {}).get('value', 0) / 1000
      elif obj.get('metric') == 'http_req_failed' and obj.get('type') == 'Point':
        error_rate = obj.get('data', {}).get('value', 0) * 100
      elif obj.get('metric') == 'http_reqs' and obj.get('type') == 'Point':
        total_reqs = int(obj.get('data', {}).get('value', 0))
    except:
      pass
  
  print(f"\n✓ Checks:     {checks_rate:.1f}%")
  print(f"✓ p95 latency: {p95_latency:.2f}ms")
  print(f"✓ Error rate:  {error_rate:.2f}%")
  print(f"✓ Total reqs:  {total_reqs}")
  
except Exception as e:
  pass
PYEOF

log_success "Resultados guardados en: $OUTPUT"

exit $K6_EXIT
