#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="localhost:32000/mubench"
NAMESPACE="realistic"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

build_push() {
  local name="$1"
  local dir="$2"
  local image="${REGISTRY}/${name}:v1"

  log "Building ${image}"
  docker build -t "${image}" "${dir}"
  log "Pushing ${image}"
  docker push "${image}"
}

log "Enabling MicroK8s registry addon"
microk8s enable registry >/dev/null 2>&1 || true

build_push "auth-service" "${ROOT_DIR}/auth-service"
build_push "data-service" "${ROOT_DIR}/data-service"
build_push "api-service" "${ROOT_DIR}/api-service"

log "Applying manifests"

microk8s kubectl apply -f "${ROOT_DIR}/k8s/00-namespace.yaml"
microk8s kubectl apply -f "${ROOT_DIR}/k8s/01-postgres.yaml"
microk8s kubectl apply -f "${ROOT_DIR}/k8s/02-services.yaml"
microk8s kubectl apply -f "${ROOT_DIR}/k8s/04-servicemonitor.yaml"
microk8s kubectl apply -f "${ROOT_DIR}/k8s/05-prometheusrule.yaml"

# Aplicar secreto TLS e Ingress NGINX
if [ -f "${ROOT_DIR}/k8s/ingress-tls-secret.yaml" ]; then
  microk8s kubectl apply -f "${ROOT_DIR}/k8s/ingress-tls-secret.yaml"
fi
if [ -f "${ROOT_DIR}/k8s/ingress-nginx.yaml" ]; then
  microk8s kubectl apply -f "${ROOT_DIR}/k8s/ingress-nginx.yaml"
fi
# Aplicar Gateway y VirtualService Istio (si existen)
if [ -f "${ROOT_DIR}/../Add-on/Istio/istio-gateway-tls.yaml" ]; then
  microk8s kubectl apply -f "${ROOT_DIR}/../Add-on/Istio/istio-gateway-tls.yaml"
fi

# Aplicar Ingress Kong (si existe)
if [ -f "${ROOT_DIR}/../Add-on/Kong/kong-ingress-tls.yaml" ]; then
  microk8s kubectl apply -f "${ROOT_DIR}/../Add-on/Kong/kong-ingress-tls.yaml"
fi

if python3 "${ROOT_DIR}/generate-experiment-comparison-rule.py"; then
  microk8s kubectl apply -f "${ROOT_DIR}/k8s/06-experiment-comparison-rule.yaml"
else
  log "Skipping experiment comparison rule (missing/invalid consolidated CSV)"
fi

log "Restarting app deployments to pull updated images"
microk8s kubectl rollout restart deployment/auth-service -n "${NAMESPACE}"
microk8s kubectl rollout restart deployment/data-service -n "${NAMESPACE}"
microk8s kubectl rollout restart deployment/api-service -n "${NAMESPACE}"

log "Waiting for deployments"
microk8s kubectl rollout status deployment/postgres -n "${NAMESPACE}" --timeout=180s
microk8s kubectl rollout status deployment/auth-service -n "${NAMESPACE}" --timeout=180s
microk8s kubectl rollout status deployment/data-service -n "${NAMESPACE}" --timeout=180s
microk8s kubectl rollout status deployment/api-service -n "${NAMESPACE}" --timeout=180s

log "Port-forward auth-service on 18082 for local login test"
pkill -f "port-forward.*auth-service" || true
nohup microk8s kubectl port-forward -n "${NAMESPACE}" svc/auth-service 18082:8080 >/tmp/realistic-auth-pf.log 2>&1 &
sleep 3

log "Done. Run smoke test: ${ROOT_DIR}/k8s/03-smoke-test.sh"
log "API NodePort: http://127.0.0.1:30081"
log "AUTH port-forward: http://127.0.0.1:18082"

chmod +x "${ROOT_DIR}/publish-grafana-dashboard.sh"
"${ROOT_DIR}/publish-grafana-dashboard.sh" || true
