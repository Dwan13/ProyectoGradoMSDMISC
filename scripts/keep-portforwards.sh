#!/usr/bin/env bash
# Mantiene los 3 port-forwards (Grafana, Prometheus, K8s Dashboard) vivos.
# Si alguno muere, lo relanza automáticamente.
# Uso: nohup bash scripts/keep-portforwards.sh > /tmp/pf-keeper.log 2>&1 &

mkdir -p /tmp/pf-logs

declare -A PF=(
  [grafana]="-n monitoring svc/prometheus-grafana 3000:80"
  [prom]="-n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  [dash]="-n kube-system svc/kubernetes-dashboard 8443:443"
)

launch() {
  local name="$1" args="$2"
  echo "[$(date +%T)] launching $name"
  nohup microk8s kubectl $args --address 0.0.0.0 \
    >> /tmp/pf-logs/$name.log 2>&1 &
  echo $! > /tmp/pf-logs/$name.pid
}

# kill any leftovers
pkill -f "kubectl.*port-forward" 2>/dev/null
sleep 2

for n in "${!PF[@]}"; do
  args="${PF[$n]}"
  # microk8s kubectl wrapper expects: -n NS port-forward svc/.. PORT
  ns=$(echo "$args" | awk '{print $2}')
  svc=$(echo "$args" | awk '{print $3}')
  port=$(echo "$args" | awk '{print $4}')
  launch "$n" "-n $ns port-forward $svc $port"
done

# supervisor loop
while true; do
  sleep 15
  for n in "${!PF[@]}"; do
    pid=$(cat /tmp/pf-logs/$n.pid 2>/dev/null)
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "[$(date +%T)] $n died (pid=$pid), restarting"
      args="${PF[$n]}"
      ns=$(echo "$args" | awk '{print $2}')
      svc=$(echo "$args" | awk '{print $3}')
      port=$(echo "$args" | awk '{print $4}')
      launch "$n" "-n $ns port-forward $svc $port"
    fi
  done
done
