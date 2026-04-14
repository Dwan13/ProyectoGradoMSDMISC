#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="realistic"
CONTROL="${1:-}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

if [[ -z "${CONTROL}" ]]; then
  echo "Usage: $0 <baseline|c1|c2|c3|c4>"
  exit 1
fi

case "${CONTROL}" in
  baseline)
    log "Resetting all controls to baseline"
    microk8s kubectl delete -f "${ROOT_DIR}/k8s/07-c1-ingress-gateway.yaml" --ignore-not-found
    microk8s kubectl delete -f "${ROOT_DIR}/k8s/08-c3-networkpolicy.yaml" --ignore-not-found
    microk8s kubectl label namespace "${NS}" linkerd.io/inject- --overwrite >/dev/null 2>&1 || true
    microk8s kubectl set env deployment/api-service -n "${NS}" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600
    microk8s kubectl rollout restart deployment/api-service -n "${NS}"
    microk8s kubectl rollout status deployment/api-service -n "${NS}" --timeout=180s
    ;;
  c1)
    log "Applying Control 1 (API Gateway via NGINX Ingress)"
    microk8s enable ingress >/dev/null 2>&1 || true
    microk8s kubectl apply -f "${ROOT_DIR}/k8s/07-c1-ingress-gateway.yaml"
    ;;
  c2)
    log "Applying Control 2 (mTLS mesh if Linkerd exists)"
    if microk8s kubectl get ns linkerd >/dev/null 2>&1; then
      microk8s kubectl label namespace "${NS}" linkerd.io/inject=enabled --overwrite
      microk8s kubectl rollout restart deployment/auth-service -n "${NS}"
      microk8s kubectl rollout restart deployment/api-service -n "${NS}"
      microk8s kubectl rollout restart deployment/data-service -n "${NS}"
      microk8s kubectl rollout status deployment/auth-service -n "${NS}" --timeout=180s
      microk8s kubectl rollout status deployment/api-service -n "${NS}" --timeout=180s
      microk8s kubectl rollout status deployment/data-service -n "${NS}" --timeout=180s
    else
      log "Linkerd namespace not found. Skipping C2 apply."
      exit 2
    fi
    ;;
  c3)
    log "Applying Control 3 (NetworkPolicies)"
    microk8s kubectl apply -f "${ROOT_DIR}/k8s/08-c3-networkpolicy.yaml"
    ;;
  c4)
    log "Applying Control 4 (API rate limiting)"
    microk8s kubectl set env deployment/api-service -n "${NS}" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=120
    microk8s kubectl rollout restart deployment/api-service -n "${NS}"
    microk8s kubectl rollout status deployment/api-service -n "${NS}" --timeout=180s
    ;;
  *)
    echo "Unknown control: ${CONTROL}"
    exit 1
    ;;
esac

log "Done: ${CONTROL}"
