#!/usr/bin/env bash
# ==============================================================================
# factorial-bootstrap.sh
#
# Prepara el cluster MicroK8s en estado conocido para la campaña factorial:
#   4 controles (C1..C4) x 3 variantes x 4 cargas (1,5,10,20 VUS) x 8 réplicas
#   = 384 ejecuciones
#
# Idempotente: se puede ejecutar varias veces sin romper estado.
#
# Pasos:
#   0) Verifica MicroK8s y addons requeridos
#   1) Crea/asegura namespace `realistic`
#   2) Despliega Postgres + secret + migrations (productos)
#   3) Despliega api-service / auth-service / data-service (baseline)
#   4) Crea TLS secret `realistic-tls` (autofirmado para realistic.local)
#   5) Asegura Ingress nginx (público) + Kong ingress
#   6) Aplica ServiceMonitors / PrometheusRule
#   7) Valida Kong CRDs (KongPlugin) y webhooks de mesh (istio, linkerd)
#   8) Smoke test (login + create + read en https://localhost)
#
# Uso:
#   bash scripts/factorial-bootstrap.sh
#   bash scripts/factorial-bootstrap.sh --skip-smoke
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${ROOT_DIR}/RealisticServices/k8s"
NS="realistic"

SKIP_SMOKE=false
[[ "${1:-}" == "--skip-smoke" ]] && SKIP_SMOKE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[bootstrap]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*"; exit 1; }

# ------------------------------------------------------------------------------
# 0) Pre-flight
# ------------------------------------------------------------------------------
log "0) Verificando MicroK8s y addons"
microk8s status >/dev/null 2>&1 || fail "MicroK8s no está corriendo. Ejecuta: microk8s start"

REQUIRED_ADDONS=(dns hostpath-storage ingress metrics-server helm3 istio linkerd)
STATUS_OUT="$(microk8s status --format short 2>/dev/null)"
for addon in "${REQUIRED_ADDONS[@]}"; do
  if echo "${STATUS_OUT}" | grep -qE "^(core|community)/${addon}: enabled"; then
    ok "addon ${addon} habilitado"
  else
    warn "addon ${addon} NO habilitado"
  fi
done

command -v kubectl >/dev/null || fail "kubectl no encontrado en PATH"
kubectl cluster-info >/dev/null 2>&1 || fail "kubectl no puede conectar al cluster"

# Kong CRDs (instalado fuera de microk8s addons)
if ! kubectl get crd kongplugins.configuration.konghq.com >/dev/null 2>&1; then
  warn "Kong CRDs no instalados. Si vas a usar C1_kong / C4 instala kong via helm."
else
  ok "Kong CRDs presentes"
fi

# Prometheus (kube-prometheus-stack)
if ! kubectl get ns monitoring >/dev/null 2>&1; then
  warn "namespace 'monitoring' ausente: las métricas CPU/MEM no estarán disponibles"
else
  ok "namespace monitoring presente"
fi

# ------------------------------------------------------------------------------
# 1) Namespace
# ------------------------------------------------------------------------------
log "1) Namespace ${NS}"
kubectl apply -f "${K8S_DIR}/00-namespace.yaml"
# Resetear injection labels para C2 baseline (deshabilitar sidecars por defecto)
kubectl label ns "${NS}" istio-injection=disabled --overwrite >/dev/null
kubectl label ns "${NS}" linkerd.io/inject- >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 2) Postgres
# ------------------------------------------------------------------------------
log "2) Postgres + secret + migrations"
kubectl apply -f "${K8S_DIR}/01-postgres.yaml"
kubectl -n "${NS}" rollout status deploy/postgres --timeout=120s

# ------------------------------------------------------------------------------
# 3) Servicios baseline (sin sidecar, sin policies)
# ------------------------------------------------------------------------------
log "3) Servicios api/auth/data (baseline)"
kubectl apply -f "${K8S_DIR}/02-services.yaml"
kubectl -n "${NS}" rollout status deploy/auth-service  --timeout=120s
kubectl -n "${NS}" rollout status deploy/data-service  --timeout=120s
kubectl -n "${NS}" rollout status deploy/api-service   --timeout=120s

# ------------------------------------------------------------------------------
# 4) TLS secret realistic-tls (idempotente)
# ------------------------------------------------------------------------------
log "4) TLS secret realistic-tls"
if ! kubectl -n "${NS}" get secret realistic-tls >/dev/null 2>&1; then
  TMPDIR="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "${TMPDIR}/tls.key" -out "${TMPDIR}/tls.crt" \
    -subj "/CN=realistic.local/O=mubench" \
    -addext "subjectAltName=DNS:realistic.local,DNS:localhost" >/dev/null 2>&1
  kubectl -n "${NS}" create secret tls realistic-tls \
    --cert="${TMPDIR}/tls.crt" --key="${TMPDIR}/tls.key"
  rm -rf "${TMPDIR}"
  ok "secret realistic-tls creado"
else
  ok "secret realistic-tls ya existe"
fi

# ------------------------------------------------------------------------------
# 5) Ingress nginx (público) + Kong ingress
# ------------------------------------------------------------------------------
log "5) Ingress nginx (C1_baseline / C1_istio)"
if [[ -f "${K8S_DIR}/ingress-nginx-rewrite.yaml" ]]; then
  kubectl apply -f "${K8S_DIR}/ingress-nginx-rewrite.yaml"
fi

log "5b) Kong ingress (C1_kong / C4)"
if kubectl get crd kongplugins.configuration.konghq.com >/dev/null 2>&1; then
  if [[ -f "${K8S_DIR}/07-c1-kong-real.yaml" ]]; then
    kubectl apply -f "${K8S_DIR}/07-c1-kong-real.yaml"
  fi
  # KongPlugins de rate limit
  [[ -f "${K8S_DIR}/09-c4-ratelimit-moderate.yaml" ]] && kubectl apply -f "${K8S_DIR}/09-c4-ratelimit-moderate.yaml"
  [[ -f "${K8S_DIR}/09-c4-ratelimit-strict.yaml" ]]   && kubectl apply -f "${K8S_DIR}/09-c4-ratelimit-strict.yaml"
  # Anular cualquier annotation residual: dejar Kong ingress sin plugin (C4_baseline)
  kubectl -n "${NS}" annotate ingress kong-realistic-ingress konghq.com/plugins- --overwrite >/dev/null 2>&1 || true
  ok "Kong ingress + plugins listos (sin plugin activo)"
else
  warn "saltando Kong (CRDs no instalados)"
fi

# ------------------------------------------------------------------------------
# 6) Observabilidad
# ------------------------------------------------------------------------------
log "6) ServiceMonitor + PrometheusRule"
[[ -f "${K8S_DIR}/04-servicemonitor.yaml" ]] && kubectl apply -f "${K8S_DIR}/04-servicemonitor.yaml" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 7) Limpieza de artefactos previos (NetworkPolicy / PeerAuth / annotations mesh)
# ------------------------------------------------------------------------------
log "7) Limpieza de policies residuales (estado baseline)"
kubectl -n "${NS}" delete networkpolicy --all >/dev/null 2>&1 || true
kubectl -n "${NS}" delete peerauthentication --all >/dev/null 2>&1 || true
# Quitar annotations de mesh inject de los deployments (vuelven a ser baseline)
for d in api-service auth-service data-service; do
  kubectl -n "${NS}" patch deploy "$d" --type=json \
    -p='[{"op":"remove","path":"/spec/template/metadata/annotations/sidecar.istio.io~1inject"}]' \
    >/dev/null 2>&1 || true
  kubectl -n "${NS}" patch deploy "$d" --type=json \
    -p='[{"op":"remove","path":"/spec/template/metadata/annotations/linkerd.io~1inject"}]' \
    >/dev/null 2>&1 || true
done

# ------------------------------------------------------------------------------
# 8) Smoke test
# ------------------------------------------------------------------------------
if [[ "${SKIP_SMOKE}" == "true" ]]; then
  warn "Smoke test omitido (--skip-smoke)"
else
  log "8) Smoke test (login + create + read)"
  sleep 3
  TOKEN=$(curl -sk -m 10 -H "Host: realistic.local" -H "Content-Type: application/json" \
    -d '{"username":"demo","password":"demo123"}' \
    https://localhost/auth/login \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("access_token") or d.get("token",""))' 2>/dev/null || echo "")
  if [[ -z "$TOKEN" ]]; then
    fail "Smoke test FALLA: no se obtuvo token (verifica auth-service y rutas /auth)"
  fi
  ok "smoke OK (token recibido, ${#TOKEN} chars)"
fi

ok "Bootstrap completado. Cluster en estado BASELINE para los 12 escenarios."
echo ""
echo "Próximos pasos:"
echo "  bash scripts/factorial-apply-scenario.sh <control> <variant>"
echo "  python3 scripts/run-factorial-campaign.py --vus 1 5 10 20 --replicas 8"
