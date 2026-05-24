#!/usr/bin/env bash
# monitoring-up.sh
# Levanta el stack de observabilidad (Grafana + K8s Dashboard + port-forwards).
# Prometheus / kube-state-metrics / node-exporter NO se tocan: siguen siempre
# arriba en background recolectando.
#
# Uso:   bash scripts/monitoring-up.sh
# Apaga: bash scripts/monitoring-down.sh

set -euo pipefail

kctl() { microk8s kubectl "$@"; }

log()  { echo -e "\033[0;34m[mon-up]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[ ok ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

log "Escalando Grafana, Dashboard y operator a 1..."
kctl -n monitoring scale deploy prometheus-grafana                  --replicas=1 >/dev/null
kctl -n monitoring scale deploy prometheus-kube-prometheus-operator --replicas=1 >/dev/null
kctl -n monitoring scale deploy prometheus-kube-state-metrics       --replicas=1 >/dev/null
kctl -n kube-system scale deploy kubernetes-dashboard               --replicas=1 >/dev/null
kctl -n kube-system scale deploy dashboard-metrics-scraper          --replicas=1 >/dev/null
ok "Escalados a 1"

log "Esperando readiness (hasta 90s)..."
kctl -n monitoring  rollout status deploy/prometheus-grafana                 --timeout=90s
kctl -n kube-system rollout status deploy/kubernetes-dashboard               --timeout=90s
kctl -n monitoring  rollout status deploy/prometheus-kube-state-metrics      --timeout=60s

log "Limpiando port-forwards previos..."
pkill -f "kubectl.*port-forward"      2>/dev/null || true
pkill -f "microk8s.*dashboard-proxy"  2>/dev/null || true
pkill -f "keep-portforwards"          2>/dev/null || true
sleep 2

mkdir -p /tmp/pf-logs

log "Lanzando port-forward Grafana (3000)..."
nohup microk8s kubectl -n monitoring port-forward --address 0.0.0.0 \
  svc/prometheus-grafana 3000:80 > /tmp/pf-logs/grafana.log 2>&1 &
disown

log "Lanzando port-forward Prometheus (9090)..."
nohup microk8s kubectl -n monitoring port-forward --address 0.0.0.0 \
  svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/pf-logs/prom.log 2>&1 &
disown

log "Lanzando dashboard-proxy (10443)..."
nohup microk8s dashboard-proxy > /tmp/pf-logs/dashproxy.log 2>&1 &
disown

sleep 8

log "Verificando endpoints..."
fail=0
for u in "http://127.0.0.1:3000/api/health|Grafana    http://localhost:3000" \
         "http://127.0.0.1:9090/-/healthy|Prometheus http://localhost:9090" \
         "https://127.0.0.1:10443/|Dashboard  https://localhost:10443"; do
  url="${u%%|*}"; name="${u##*|}"
  code=$(curl -sk -m 5 -o /dev/null -w "%{http_code}" "$url" || echo "000")
  if [[ "$code" == "200" || "$code" == "302" ]]; then
    ok "$name  -> $code"
  else
    warn "$name  -> $code (no responde aún, dale 10s más)"
    fail=1
  fi
done

log "Generando token admin K8s Dashboard (24h)..."
kctl -n kube-system create token dashboard-admin --duration=24h > /tmp/dash-token.txt
ok "Token guardado en /tmp/dash-token.txt ($(wc -c < /tmp/dash-token.txt) bytes)"

echo
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║  ENDPOINTS LISTOS (abrir en navegador de Windows)                 ║
╠══════════════════════════════════════════════════════════════════╣
║  Grafana    →  http://localhost:3000                              ║
║               user: admin                                          ║
║               pass: gjBgdk9aXrs2bCuZDnACjSry04I7my3ixPsqMoXi      ║
║                                                                    ║
║  Prometheus →  http://localhost:9090                              ║
║                                                                    ║
║  K8s Dash   →  https://localhost:10443                            ║
║               Token: cat /tmp/dash-token.txt                       ║
╚══════════════════════════════════════════════════════════════════╝
EOF
echo
log "Para apagar (libera ~300MB RAM, Prometheus sigue scrapeando):"
log "  bash scripts/monitoring-down.sh"

exit $fail
