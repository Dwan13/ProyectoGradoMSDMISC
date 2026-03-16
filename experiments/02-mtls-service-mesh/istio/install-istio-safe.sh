#!/usr/bin/env bash
set -euo pipefail

echo "[istio] Instalacion segura (perfil demo minimo)"

if ! command -v istioctl >/dev/null 2>&1; then
  echo "[istio] ERROR: istioctl no esta instalado en PATH"
  echo "[istio] Instalar manualmente y reintentar"
  exit 1
fi

istioctl install --set profile=demo -y
microk8s kubectl label namespace default istio-injection=enabled --overwrite
microk8s kubectl rollout restart deploy/s0 deploy/s1 deploy/sdb1 -n default
microk8s kubectl rollout status deploy/s0 -n default --timeout=180s
microk8s kubectl rollout status deploy/s1 -n default --timeout=180s
microk8s kubectl rollout status deploy/sdb1 -n default --timeout=180s

echo "[istio] Instalacion completada"
