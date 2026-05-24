#!/usr/bin/env bash
# monitoring-down.sh
# Apaga SÓLO las UIs (Grafana + K8s Dashboard) y mata los port-forwards.
# Libera ~300 MB de RAM.
#
# IMPORTANTE: Prometheus, kube-state-metrics, node-exporter y prometheus-operator
# SIGUEN ARRIBA en background. La recolección de CPU/mem/HTTP métricas continúa
# sin interrupción → cuando vuelvas a levantar con monitoring-up.sh tendrás
# históricos completos.
#
# Uso: bash scripts/monitoring-down.sh

set -euo pipefail

kctl() { microk8s kubectl "$@"; }

log()  { echo -e "\033[0;34m[mon-dn]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[ ok ]\033[0m $*"; }

log "Matando port-forwards y dashboard-proxy..."
pkill -f "kubectl.*port-forward"     2>/dev/null || true
pkill -f "microk8s.*dashboard-proxy" 2>/dev/null || true
pkill -f "keep-portforwards"         2>/dev/null || true
sleep 2
ok "Procesos detenidos"

log "Escalando UIs a 0..."
kctl -n monitoring  scale deploy prometheus-grafana         --replicas=0 >/dev/null
kctl -n kube-system scale deploy kubernetes-dashboard       --replicas=0 >/dev/null
kctl -n kube-system scale deploy dashboard-metrics-scraper  --replicas=0 >/dev/null
ok "UIs apagadas"

log "Estado componentes que SIGUEN ARRIBA (recolección activa):"
kctl -n monitoring  get pod -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready 2>/dev/null \
  | grep -E "prometheus-prometheus|kube-state|operator|alertmanager" || true
kctl -n monitoring  get daemonset node-exporter-minimal -o custom-columns=NAME:.metadata.name,READY:.status.numberReady,DESIRED:.status.desiredNumberScheduled 2>/dev/null

echo
ok "Listo. RAM liberada (~300MB)."
log "Prometheus sigue scrapeando en background."
log "Para volver a ver Grafana/Dashboard:  bash scripts/monitoring-up.sh"
