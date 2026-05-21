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
TARGET_ENV="default"
SKIP_PRECHECK=false
PRECHECK_TIMEOUT_SECONDS="${PRECHECK_TIMEOUT_SECONDS:-90}"
SECURITY_MODE="normal"
K6_SCRIPT_OVERRIDE=""
ATTACK_PROFILE="${ATTACK_PROFILE:-advanced}"

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
    --target-env) TARGET_ENV="$2"; shift 2 ;;
    --security-mode) SECURITY_MODE="$2"; shift 2 ;;
    --k6-script) K6_SCRIPT_OVERRIDE="$2"; shift 2 ;;
    --skip-precheck) SKIP_PRECHECK=true; shift ;;
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
  --target-env <default|postgres-real>
                                 Entorno objetivo (default: default)
  --security-mode <normal|attack>
                                 Modo de ejecución del flujo (default: normal)
  --k6-script <path>             Script k6 alternativo (opcional)
  --skip-precheck                Omitir gate de readiness (no recomendado)
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

if [[ "$SECURITY_MODE" != "normal" && "$SECURITY_MODE" != "attack" ]]; then
  log_error "--security-mode debe ser normal o attack"
  exit 1
fi

if [[ -n "$K6_SCRIPT_OVERRIDE" ]]; then
  K6_SCRIPT="$K6_SCRIPT_OVERRIDE"
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
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        case "$variant" in
          baseline)
            AUTH_BASE="https://localhost/auth"
            API_BASE="https://localhost/api"
            HOST_HEADER="real-postgres.local"
            INSECURE_TLS="true"
            ;;
          istio)
            AUTH_BASE="http://localhost:31880"
            API_BASE="http://localhost:31880"
            HOST_HEADER="real-postgres.local"
            INSECURE_TLS="false"
            ;;
          kong)
            AUTH_BASE="https://localhost:30443"
            API_BASE="https://localhost:30443"
            HOST_HEADER="real-postgres.local"
            INSECURE_TLS="true"
            ;;
          *)
            log_error "Variante C1 desconocida para postgres-real: $variant"
            return 1
            ;;
        esac
        return 0
      fi

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
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        AUTH_BASE="http://localhost:30184"
        API_BASE="http://localhost:30181"
        HOST_HEADER=""
        INSECURE_TLS="false"
        return 0
      fi
      # C2 usa HTTP en NodePorts (mTLS es transparente a cliente)
      AUTH_BASE="http://localhost:30084"
      API_BASE="http://localhost:30081"
      HOST_HEADER=""
      INSECURE_TLS="false"
      ;;
    C3)
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        AUTH_BASE="http://localhost:30184"
        API_BASE="http://localhost:30181"
        HOST_HEADER=""
        INSECURE_TLS="false"
        return 0
      fi
      # C3 igual a C2 (network policies no cambian endpoints)
      AUTH_BASE="http://localhost:30084"
      API_BASE="http://localhost:30081"
      HOST_HEADER=""
      INSECURE_TLS="false"
      ;;
    C4)
      if [ "$TARGET_ENV" = "postgres-real" ]; then
        # C4 rate limiting is enforced at ingress, so benchmark traffic must
        # traverse ingress instead of direct NodePort service endpoints.
        AUTH_BASE="https://localhost/auth"
        API_BASE="https://localhost/api"
        HOST_HEADER=""
        INSECURE_TLS="true"
        return 0
      fi
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

build_curl_args() {
  CURL_ARGS=(-sS --max-time 8)
  if [[ "$INSECURE_TLS" == "true" ]]; then
    CURL_ARGS+=(-k)
  fi
  if [[ -n "$HOST_HEADER" ]]; then
    CURL_ARGS+=(-H "Host: $HOST_HEADER")
  fi
}

run_readiness_gate() {
  local wait_seconds="$1"
  local step_seconds=5
  local attempts=$(( wait_seconds / step_seconds ))
  if [[ "$attempts" -lt 1 ]]; then
    attempts=1
  fi

  build_curl_args

  for ((i=1; i<=attempts; i++)); do
    local login_resp token profile_code

    login_resp="$(curl "${CURL_ARGS[@]}" \
      -H 'Content-Type: application/json' \
      -X POST "${AUTH_BASE}/login" \
      -d '{"username":"demo","password":"demo123"}' 2>/dev/null || true)"

    token="$(python3 - <<'PY' "$login_resp"
import json,sys
raw = sys.argv[1]
try:
    obj = json.loads(raw)
    print(obj.get('access_token',''))
except Exception:
    print('')
PY
)"

    if [[ -n "$token" ]]; then
      profile_code="$(curl "${CURL_ARGS[@]}" \
        -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $token" \
        "${API_BASE}/profile?user_id=1" 2>/dev/null || true)"

      if [[ "$profile_code" == "200" ]]; then
        log_success "Readiness gate OK (login/profile) en intento $i/$attempts"
        return 0
      fi
    fi

    log_warn "Readiness gate pendiente (intento $i/$attempts), reintentando..."
    sleep "$step_seconds"
  done

  return 1
}

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
Target Env:       $TARGET_ENV
Auth Endpoint:    $AUTH_BASE
API Endpoint:     $API_BASE
Host Header:      ${HOST_HEADER:-"(none)"}
TLS Insecure:     $INSECURE_TLS
Security Mode:    $SECURITY_MODE
Attack Profile:   $ATTACK_PROFILE
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

PF_PID=""
if [[ "$TARGET_ENV" == "postgres-real" && "$CONTROL" == "C1" && "$VARIANT" == "istio" ]]; then
  log_info "Iniciando port-forward temporal a istio-ingressgateway (31880->80)..."
  kubectl port-forward -n istio-system svc/istio-ingressgateway 31880:80 >/tmp/mubench-istio-pf.log 2>&1 &
  PF_PID=$!
  sleep 2
fi

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if [[ "$SKIP_PRECHECK" != "true" ]]; then
  log_info "Aplicando readiness gate uniforme (timeout=${PRECHECK_TIMEOUT_SECONDS}s)..."
  if ! run_readiness_gate "$PRECHECK_TIMEOUT_SECONDS"; then
    log_error "Readiness gate falló: login/profile no estabilizó antes del benchmark"
    exit 42
  fi
else
  log_warn "Readiness gate omitido por --skip-precheck"
fi

log_info "Iniciando k6 benchmark..."
echo ""

set +e

k6 run \
  -e AUTH_BASE="$AUTH_BASE" \
  -e API_BASE="$API_BASE" \
  -e K6_INSECURE_SKIP_TLS_VERIFY="$INSECURE_TLS" \
  -e HOST_HEADER="$HOST_HEADER" \
  -e SECURITY_MODE="$SECURITY_MODE" \
  -e ATTACK_PROFILE="$ATTACK_PROFILE" \
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
import json

try:
  durations = []
  failed_reqs = 0
  total_failed_points = 0
  total_reqs = 0
  checks_total = 0
  checks_ok = 0

  with open('$OUTPUT') as f:
    for line in f:
      try:
        obj = json.loads(line)
      except Exception:
        continue

      if obj.get('type') != 'Point':
        continue

      metric = obj.get('metric')
      value = obj.get('data', {}).get('value', 0)

      if metric == 'http_req_duration':
        durations.append(float(value))
      elif metric == 'http_req_failed':
        total_failed_points += 1
        failed_reqs += int(value)
      elif metric == 'http_reqs':
        total_reqs += int(value)
      elif metric == 'checks':
        checks_total += 1
        checks_ok += int(value)

  durations.sort()
  p95_latency = durations[min(int(len(durations) * 0.95), len(durations) - 1)] if durations else 0
  error_rate = (failed_reqs / total_failed_points * 100) if total_failed_points else 0
  checks_rate = (checks_ok / checks_total * 100) if checks_total else 0

  print(f"\n✓ Checks:     {checks_rate:.1f}%")
  print(f"✓ p95 latency: {p95_latency:.2f}ms")
  print(f"✓ Error rate:  {error_rate:.2f}%")
  print(f"✓ Total reqs:  {total_reqs}")
except Exception:
  pass
PYEOF

log_success "Resultados guardados en: $OUTPUT"

exit $K6_EXIT
