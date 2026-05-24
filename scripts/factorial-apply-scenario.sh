#!/usr/bin/env bash
# ==============================================================================
# factorial-apply-scenario.sh
#
# Configura el cluster para UN escenario específico de la campaña factorial.
# El script SIEMPRE resetea a baseline antes de aplicar para evitar contaminación.
#
# Escenarios soportados (12):
#   C1 baseline | C1 istio | C1 kong
#   C2 baseline | C2 istio_mtls | C2 linkerd_mtls
#   C3 baseline | C3 basic | C3 strict
#   C4 baseline | C4 moderate | C4 strict
#
# Uso:
#   bash scripts/factorial-apply-scenario.sh C1 baseline
#   bash scripts/factorial-apply-scenario.sh C2 istio_mtls
#   bash scripts/factorial-apply-scenario.sh C4 strict
#
# Devuelve por stdout (eval-friendly):
#   API_URL=...  AUTH_URL=...  HOST_HEADER=...
# ==============================================================================
set -euo pipefail

CONTROL="${1:-}"
VARIANT="${2:-}"
NS="realistic"

if [[ -z "$CONTROL" || -z "$VARIANT" ]]; then
  echo "Uso: $0 <C1|C2|C3|C4> <variant>" >&2
  exit 1
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[apply]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[warn]${NC} $*" >&2; }
fail() { echo -e "${RED}[fail]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${ROOT_DIR}/RealisticServices/k8s"

# ------------------------------------------------------------------------------
# RESET A BASELINE (limpio)
# ------------------------------------------------------------------------------
reset_baseline() {
  log "reset → baseline"
  # NetworkPolicies (C3)
  kubectl -n "${NS}" delete networkpolicy --all >/dev/null 2>&1 || true
  # PeerAuthentication / AuthorizationPolicy (C2 istio) — usar FQ porque
  # `authorizationpolicy` también existe en linkerd y kubectl resuelve sólo uno.
  kubectl -n "${NS}" delete peerauthentication --all >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete authorizationpolicies.security.istio.io --all >/dev/null 2>&1 || true
  # Linkerd policy (C2 linkerd)
  kubectl -n "${NS}" delete server --all >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete serverauthorization --all >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete authorizationpolicies.policy.linkerd.io --all >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete meshtlsauthentication --all >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete networkauthentication --all >/dev/null 2>&1 || true
  # Istio Gateway / VirtualService (C1 istio)
  kubectl -n "${NS}" delete gateway realistic-gateway --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete virtualservice realistic-vs --ignore-not-found >/dev/null 2>&1 || true
  # Mini-WAF Lua (C1/istio y C1/kong) — siempre limpiar antes de aplicar variante
  kubectl -n istio-system delete envoyfilter realistic-waf-sqli --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${NS}" delete kongplugin realistic-waf-sqli --ignore-not-found >/dev/null 2>&1 || true
  # Quitar plugin de Kong ingress (C4 y C1/kong WAF)
  kubectl -n "${NS}" annotate ingress kong-realistic-ingress \
    konghq.com/plugins- --overwrite >/dev/null 2>&1 || true
  # Quitar annotations mesh de pods (C2)
  local need_rollout=0
  for d in api-service auth-service data-service; do
    if kubectl -n "${NS}" get deploy "$d" -o jsonpath='{.spec.template.metadata.annotations}' 2>/dev/null \
        | grep -qE 'sidecar\.istio\.io/inject|linkerd\.io/inject|config\.linkerd\.io/default-inbound-policy'; then
      kubectl -n "${NS}" patch deploy "$d" --type=json \
        -p='[{"op":"remove","path":"/spec/template/metadata/annotations/sidecar.istio.io~1inject"}]' \
        >/dev/null 2>&1 || true
      kubectl -n "${NS}" patch deploy "$d" --type=json \
        -p='[{"op":"remove","path":"/spec/template/metadata/annotations/linkerd.io~1inject"}]' \
        >/dev/null 2>&1 || true
      kubectl -n "${NS}" patch deploy "$d" --type=json \
        -p='[{"op":"remove","path":"/spec/template/metadata/annotations/config.linkerd.io~1default-inbound-policy"}]' \
        >/dev/null 2>&1 || true
      need_rollout=1
    fi
  done
  # Reset namespace label (istio injection disabled)
  kubectl label ns "${NS}" istio-injection=disabled --overwrite >/dev/null 2>&1
  if [[ $need_rollout -eq 1 ]]; then
    log "rollout para retirar sidecars (~30s)"
    for d in api-service auth-service data-service; do
      kubectl -n "${NS}" rollout restart deploy/"$d" >/dev/null
    done
    for d in api-service auth-service data-service; do
      kubectl -n "${NS}" rollout status deploy/"$d" --timeout=120s >/dev/null
    done
  fi
}

# ------------------------------------------------------------------------------
# Inyección sidecars (Istio o Linkerd) por annotation a deployments
# ------------------------------------------------------------------------------
inject_istio() {
  log "inyectando sidecars Istio"
  kubectl label ns "${NS}" istio-injection=enabled --overwrite >/dev/null
  for d in api-service auth-service data-service; do
    kubectl -n "${NS}" patch deploy "$d" -p \
      '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true"}}}}}' >/dev/null
    kubectl -n "${NS}" rollout restart deploy/"$d" >/dev/null
  done
  for d in api-service auth-service data-service; do
    kubectl -n "${NS}" rollout status deploy/"$d" --timeout=180s >/dev/null
  done
  # Esperar a que sean 2/2
  for i in $(seq 1 30); do
    READY=$(kubectl -n "${NS}" get pods -l 'app in (api-service,auth-service,data-service)' \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' \
      | grep -c "true true" || true)
    [[ "$READY" -ge 3 ]] && return 0
    sleep 2
  done
  fail "sidecars Istio no llegaron a 2/2"
}

inject_linkerd() {
  log "inyectando sidecars Linkerd"
  for d in api-service auth-service data-service; do
    kubectl -n "${NS}" patch deploy "$d" -p \
      '{"spec":{"template":{"metadata":{"annotations":{"linkerd.io/inject":"enabled"}}}}}' >/dev/null
    kubectl -n "${NS}" rollout restart deploy/"$d" >/dev/null
  done
  for d in api-service auth-service data-service; do
    kubectl -n "${NS}" rollout status deploy/"$d" --timeout=180s >/dev/null
  done
  for i in $(seq 1 30); do
    READY=$(kubectl -n "${NS}" get pods -l 'app in (api-service,auth-service,data-service)' \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' \
      | grep -c "true true" || true)
    [[ "$READY" -ge 3 ]] && return 0
    sleep 2
  done
  fail "sidecars Linkerd no llegaron a 2/2"
}

# ==============================================================================
# Aplicación del escenario
# ==============================================================================
reset_baseline

API_URL=""; AUTH_URL=""; HOST_HEADER=""

case "${CONTROL}/${VARIANT}" in

  # --- C1: API Gateway -----------------------------------------------------
  C1/baseline)
    # nginx-ingress (NodePort 443 mapped to host)
    API_URL="https://realistic.local"; AUTH_URL="https://realistic.local"; HOST_HEADER="realistic.local"
    ;;
  C1/istio)
    # Istio Ingress Gateway (NodePort HTTPS 30997). NO inyectar sidecars en
    # api/auth/data: C1 mide el COMPONENTE GATEWAY, no el service mesh interno
    # (eso es C2). Replicar TLS secret a istio-system para terminar TLS allí.
    if ! kubectl -n istio-system get secret realistic-tls >/dev/null 2>&1; then
      kubectl -n "${NS}" get secret realistic-tls -o yaml \
        | sed 's/namespace: realistic/namespace: istio-system/' \
        | kubectl apply -f - >/dev/null
    fi
    kubectl apply -f "${K8S_DIR}/10-c1-istio-gateway.yaml" >/dev/null
    # Mini-WAF SQLi simétrico (Lua en Envoy) — paridad con Kong
    kubectl apply -f "${K8S_DIR}/11-c1-istio-waf-lua.yaml" >/dev/null
    # Esperar que la config del gateway propague (Envoy xDS)
    sleep 5
    API_URL="https://realistic.local:30997"; AUTH_URL="https://realistic.local:30997"; HOST_HEADER="realistic.local"
    ;;
  C1/kong)
    # Mini-WAF SQLi simétrico (Lua en OpenResty via pre-function) — paridad con Istio
    kubectl apply -f "${K8S_DIR}/12-c1-kong-waf-lua.yaml" >/dev/null
    kubectl -n "${NS}" annotate ingress kong-realistic-ingress \
      konghq.com/plugins=realistic-waf-sqli --overwrite >/dev/null
    sleep 3
    API_URL="https://realistic.local:30443"; AUTH_URL="https://realistic.local:30443"; HOST_HEADER="realistic.local"
    ;;

  # --- C2: mTLS service-to-service ----------------------------------------
  C2/baseline)
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;
  C2/istio_mtls)
    inject_istio
    # STRICT mTLS sólo sobre data-service (backend puro). api-service queda
    # PERMISSIVE para aceptar ingress sin sidecar y auth-service queda sin
    # policy: actúa como front-door público de auth (login externo legítimo).
    # AuthorizationPolicy en data-service exige principal SPIFFE del namespace.
    kubectl apply -f "${K8S_DIR}/13-c2-istio-strict.yaml" >/dev/null
    sleep 5  # propagación xDS
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;
  C2/linkerd_mtls)
    inject_linkerd
    # Server + AuthorizationPolicy estricto sólo sobre data-service.
    # default-inbound-policy=deny únicamente en data-service para que la
    # AuthorizationPolicy sea enforcada (linkerd default es all-unauthenticated).
    # auth-service queda accesible (front-door de autenticación pública).
    kubectl -n "${NS}" patch deploy data-service -p \
      '{"spec":{"template":{"metadata":{"annotations":{"config.linkerd.io/default-inbound-policy":"deny"}}}}}' >/dev/null
    kubectl -n "${NS}" rollout status deploy/data-service --timeout=120s >/dev/null
    kubectl apply -f "${K8S_DIR}/14-c2-linkerd-policy.yaml" >/dev/null
    sleep 3
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;

  # --- C3: NetworkPolicies -------------------------------------------------
  C3/baseline)
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;
  C3/basic)
    kubectl apply -f "${K8S_DIR}/08-c3-networkpolicy.yaml" >/dev/null
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;
  C3/strict)
    kubectl apply -f "${K8S_DIR}/08-c3-networkpolicy-strict.yaml" >/dev/null
    API_URL="http://localhost:30081"; AUTH_URL="http://localhost:30084"; HOST_HEADER=""
    ;;

  # --- C4: Rate Limiting (SOLO via Kong API Gateway) -----------------------
  C4/baseline)
    API_URL="https://realistic.local:30443"; AUTH_URL="https://realistic.local:30443"; HOST_HEADER="realistic.local"
    ;;
  C4/moderate)
    kubectl -n "${NS}" annotate ingress kong-realistic-ingress \
      konghq.com/plugins=ratelimit-moderate --overwrite >/dev/null
    API_URL="https://realistic.local:30443"; AUTH_URL="https://realistic.local:30443"; HOST_HEADER="realistic.local"
    ;;
  C4/strict)
    kubectl -n "${NS}" annotate ingress kong-realistic-ingress \
      konghq.com/plugins=ratelimit-strict --overwrite >/dev/null
    API_URL="https://realistic.local:30443"; AUTH_URL="https://realistic.local:30443"; HOST_HEADER="realistic.local"
    ;;

  *)
    fail "escenario desconocido: ${CONTROL}/${VARIANT}"
    ;;
esac

# Estabilización breve
sleep 2

ok "escenario ${CONTROL}/${VARIANT} aplicado"
# Salida eval-friendly por stdout (el resto va a stderr)
echo "API_URL=${API_URL}"
echo "AUTH_URL=${AUTH_URL}"
echo "HOST_HEADER=${HOST_HEADER}"
