#!/usr/bin/env bash
set -euo pipefail

echo "[linkerd] Instalacion segura"

if ! command -v linkerd >/dev/null 2>&1; then
  echo "[linkerd] ERROR: linkerd CLI no encontrado"
  echo "[linkerd] Instalar CLI y reintentar"
  exit 1
fi

# Limpiar inyeccion de Istio para evitar sidecars mixtos
microk8s kubectl label namespace default istio-injection- --overwrite >/dev/null 2>&1 || true
microk8s kubectl delete peerauthentication default -n default >/dev/null 2>&1 || true

# Reiniciar workloads base sin sidecar de Istio
microk8s kubectl rollout restart deploy/s0 deploy/s1 deploy/sdb1 -n default
microk8s kubectl rollout status deploy/s0 -n default --timeout=180s
microk8s kubectl rollout status deploy/s1 -n default --timeout=180s
microk8s kubectl rollout status deploy/sdb1 -n default --timeout=180s

linkerd check --pre
linkerd install --crds | microk8s kubectl apply -f -
linkerd install | microk8s kubectl apply -f -
linkerd check

microk8s kubectl annotate namespace default linkerd.io/inject=enabled --overwrite
microk8s kubectl rollout restart deploy/s0 deploy/s1 deploy/sdb1 -n default
microk8s kubectl rollout status deploy/s0 -n default --timeout=180s
microk8s kubectl rollout status deploy/s1 -n default --timeout=180s
microk8s kubectl rollout status deploy/sdb1 -n default --timeout=180s

echo "[linkerd] Instalacion completada"
