#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Verificando estado de Prometheus/Grafana/Dashboard..."

WSL_IP=$(hostname -I | awk '{print $1}')

PROM_OK=$(curl -sS http://127.0.0.1:30000/-/ready || true)
GRAFANA_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:30030/login || true)
K8S_DASH_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://127.0.0.1:30445/ || true)

echo "Prometheus: ${PROM_OK:-NO RESPONSE}"
echo "Grafana HTTP code: ${GRAFANA_CODE:-NO RESPONSE}"
echo "Kubernetes Dashboard HTTP code: ${K8S_DASH_CODE:-NO RESPONSE}"

echo
echo "[INFO] URLs (localhost)"
echo "Prometheus: http://localhost:30000"
echo "Grafana:    http://localhost:30030"
echo "K8s Dash:   https://localhost:30445"

echo
echo "[INFO] URLs (IP Linux/WSL, usar si localhost no abre en navegador host)"
echo "Prometheus: http://${WSL_IP}:30000"
echo "Grafana:    http://${WSL_IP}:30030"
echo "K8s Dash:   https://${WSL_IP}:30445"

echo
echo "[INFO] Nota de protocolo"
echo "- Prometheus y Grafana van por HTTP (no HTTPS en esos puertos)."
echo "- Kubernetes Dashboard va por HTTPS."

echo
echo "[INFO] Credenciales Grafana"
G_USER=$(kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-user}' | base64 -d)
G_PASS=$(kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
echo "usuario: ${G_USER}"
echo "password: ${G_PASS}"

echo
echo "[INFO] Token Dashboard (24h)"
kubectl -n kube-system create token dashboard-admin --duration=24h
