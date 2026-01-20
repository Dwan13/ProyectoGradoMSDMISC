#!/bin/bash
# ================================================================
# 🚀 Proyecto MuBench - Despliegue Automático en MicroK8s + JMeter
# ================================================================
# Autor: Dwan13
# Descripción: Despliega, configura y gestiona el entorno completo
# de muBench con observabilidad (Prometheus + Grafana + Dashboard)
# y pruebas automáticas de rendimiento con Apache JMeter.
# ================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Variables ---
PROJECT_DIR="${HOME}/muBench"
SIMULATION_DIR="${PROJECT_DIR}/WorkModelGenerator/SimulationWorkspace"
CONFIG_DIR="${PROJECT_DIR}/Configs"
MONITORING_DIR="${PROJECT_DIR}/Monitoring"
TEST_DIR="${PROJECT_DIR}/Testing"
RESULTS_DIR="${TEST_DIR}/results"
NAMESPACE="default"

PROM_LOG="/tmp/prometheus_portforward.log"
GRAFANA_LOG="/tmp/grafana_portforward.log"
DASH_LOG="/tmp/dashboard_portforward.log"
CRED_FILE="${HOME}/.mubench_credentials"

# --- Colores ---
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"; RESET="\e[0m"

log() { echo -e "${CYAN}[$(date +'%H:%M:%S')]${RESET} $*"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️ $*${RESET}"; }
error() { echo -e "${RED}❌ $*${RESET}" >&2; exit 1; }

# ================================================================
# 🧩 Funciones auxiliares
# ================================================================

wait_for_pods() {
  log "Esperando a que los pods de muBench estén corriendo..."
  for _ in {1..30}; do
    READY=$(microk8s kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E 's0|s1|sdb1|gw-nginx|api-demo' | grep -c "Running" || true)
    (( READY >= 4 )) && { success "Pods de muBench listos."; return 0; }
    sleep 5
  done
  warn "Algunos pods no están completamente listos. Continuando..."
}

enable_dashboard() {
  log "🧩 Configurando Kubernetes Dashboard..."
  sudo microk8s enable dashboard || true
  sudo microk8s enable rbac || true

  if ! sudo microk8s kubectl get sa dashboard-admin -n kube-system >/dev/null 2>&1; then
    sudo microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: dashboard-admin
    namespace: kube-system
EOF
  fi

  nohup sudo microk8s kubectl port-forward -n kube-system service/kubernetes-dashboard 10443:443 >"$DASH_LOG" 2>&1 &
  sleep 5

  DASH_TOKEN=$(sudo microk8s kubectl -n kube-system create token dashboard-admin 2>/dev/null || true)
  echo "$DASH_TOKEN"
}

# ================================================================
# 🔧 Gateway Nginx / Microservicios
# ================================================================
fix_nginx_dns() {
  log "🔧 Reconfigurando gateway gw-nginx con rutas demo y servicios simulados..."

  sudo microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-nginx-config
  namespace: default
data:
  default.conf: |
    server {
        listen 80;
        resolver 10.152.183.10 valid=10s ipv6=off;

        # --- Rutas demo ---
        location /demo/ {
            rewrite ^/demo/?(.*)\$ /\$1 break;
            proxy_pass http://api-demo.default.svc.cluster.local:80;
        }
        location / {
            proxy_pass http://api-demo.default.svc.cluster.local:80;
        }

        # --- Microservicios simulados ---
        location /service0/ {
            proxy_pass http://service0.default.svc.cluster.local:80/;
        }
        location /service1/ {
            proxy_pass http://service1.default.svc.cluster.local:80/;
        }
        location /database/ {
            proxy_pass http://service-db.default.svc.cluster.local:80/;
        }
    }
EOF

  if ! sudo microk8s kubectl get deployment gw-nginx -n default >/dev/null 2>&1; then
    warn "❌ No se encontró el deployment 'gw-nginx', se recreará..."
    sudo microk8s kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gw-nginx
  namespace: default
  labels:
    app: gw-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gw-nginx
  template:
    metadata:
      labels:
        app: gw-nginx
    spec:
      containers:
      - name: gw-nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: gw-nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: gw-nginx
  namespace: default
  labels:
    app: gw-nginx
spec:
  type: NodePort
  selector:
    app: gw-nginx
  ports:
    - name: http
      port: 80
      nodePort: 31113
EOF
  fi

  sudo microk8s kubectl rollout restart deployment gw-nginx -n default
  log "⏳ Esperando que gw-nginx esté Running..."
  for i in {1..20}; do
    STATUS=$(sudo microk8s kubectl get pods -l app=gw-nginx -n default -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    [[ "$STATUS" == "Running" ]] && { success "✅ Gateway listo."; sleep 5; return 0; }
    sleep 5
  done
  warn "⚠️ gw-nginx no alcanzó estado Running, continuaré de todas formas..."
}

# ================================================================
# 🧪 JMeter Tests
# ================================================================
check_jmeter() {
  log "Verificando instalación de JMeter..."
  command -v jmeter >/dev/null 2>&1 || { error "❌ JMeter no encontrado. Instálalo antes de continuar."; }
  success "✅ JMeter detectado correctamente."
}

run_jmeter_tests() {
  check_jmeter

  GW_PORT=$(microk8s kubectl get svc gw-nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
  GW_IP="127.0.0.1"
  [[ -z "$GW_PORT" ]] && { warn "❌ No se detectó puerto de gw-nginx"; return; }

  declare -A ENDPOINTS=(
    ["demo"]="/demo/"
    ["service0"]="/service0/"
    ["service1"]="/service1/"
    ["database"]="/database/"
  )

  mkdir -p "${RESULTS_DIR}"

  for NAME in "${!ENDPOINTS[@]}"; do
    TARGET_URL="http://${GW_IP}:${GW_PORT}${ENDPOINTS[$NAME]}"
    log "Verificando conexión con ${TARGET_URL}..."

    RETRY=0
    until curl -s --max-time 5 "$TARGET_URL" >/dev/null 2>&1 || [[ $RETRY -ge 5 ]]; do
      RETRY=$((RETRY+1))
      sleep 2
    done

    [[ $RETRY -ge 5 ]] && { warn "⚠️ ${NAME} no responde, se omitirá."; continue; }

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    RESULT_FILE="${RESULTS_DIR}/results_${NAME}_${TIMESTAMP}.jtl"

    log "🏁 Ejecutando JMeter contra ${TARGET_URL}"
    jmeter -n -t "${TEST_DIR}/mubench_baseline.jmx" \
      -JTARGET_URL="${TARGET_URL}" \
      -JTHREADS=50 \
      -JDURATION=60 \
      -l "${RESULT_FILE}" || warn "⚠️ Error al ejecutar prueba JMeter para ${NAME}"

    success "✅ Prueba ${NAME} completada. Resultados en: ${RESULT_FILE}"
  done
}

create_grafana_dashboard() {
  log "🔧 Creando dashboard rápido en Grafana..."

  GRAFANA_URL="http://localhost:3000"
  GRAFANA_USER="admin"
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' | base64 --decode)

  DASHBOARD_JSON=$(cat <<EOF
{
  "dashboard": {
    "id": null,
    "title": "MuBench JMeter Metrics",
    "uid": "mubench-jmeter",
    "timezone": "browser",
    "panels": [
      {
        "type": "graph",
        "title": "Latency (ms)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(http_request_duration_seconds_sum[1m])/rate(http_request_duration_seconds_count[1m])",
            "legendFormat": "\$job-\$instance"
          }
        ],
        "gridPos": {"x":0,"y":0,"w":12,"h":6}
      },
      {
        "type": "graph",
        "title": "Throughput (req/s)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(http_requests_total[1m])",
            "legendFormat": "\$job-\$instance"
          }
        ],
        "gridPos": {"x":12,"y":0,"w":12,"h":6}
      }
    ]
  },
  "overwrite": true
}
EOF
)

  # Crear dashboard usando API de Grafana
  curl -s -X POST -H "Content-Type: application/json" \
       -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
       -d "${DASHBOARD_JSON}" \
       "${GRAFANA_URL}/api/dashboards/db" >/dev/null

  success "✅ Dashboard 'MuBench JMeter Metrics' creado en Grafana: ${GRAFANA_URL}"
}

# ================================================================
# 🚀 Inicio de servicios
# ================================================================
start_services() {
  log "Iniciando despliegue automatizado MuBench..."
  microk8s status --wait-ready >/dev/null 2>&1 || error "❌ MicroK8s no está listo"

  wait_for_pods
  fix_nginx_dns

  log "Iniciando port-forward Prometheus y Grafana..."
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >"$PROM_LOG" 2>&1 &
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 >"$GRAFANA_LOG" 2>&1 &
  
  log "Configurando Dashboard de Kubernetes..."
  DASH_TOKEN=$(enable_dashboard || true)

  run_jmeter_tests
  create_grafana_dashboard


  log "Obteniendo credenciales..."
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' | base64 --decode)

  {
    echo "============================"
    echo "🧩 MuBench Access Credentials"
    echo "============================"
    echo
    echo "Grafana"
    echo "--------"
    echo "URL: http://localhost:3000"
    echo "Usuario: admin"
    echo "Contraseña: ${GRAFANA_PASS}"
    echo
    echo "Prometheus"
    echo "-----------"
    echo "URL: http://localhost:9090"
    echo
    echo "Kubernetes Dashboard"
    echo "---------------------"
    echo "URL: https://localhost:10443"
    echo "Token: ${DASH_TOKEN}"
  } > "${CRED_FILE}"

  chmod 600 "${CRED_FILE}"
  success "Credenciales guardadas en: ${CRED_FILE}"

  success "✅ Despliegue completo. Accesos:"
  echo -e "${CYAN}Grafana:${RESET}     http://localhost:3000"
  echo -e "${CYAN}Prometheus:${RESET}  http://localhost:9090"
  echo -e "${CYAN}Dashboard:${RESET}   https://localhost:10443"
}

# ================================================================
# 🛑 Detener servicios
# ================================================================
stop_services() {
  log "Deteniendo port-forwards..."
  sudo pkill -f "port-forward" || true
  rm -f "${PROM_LOG}" "${GRAFANA_LOG}" "${DASH_LOG}"
  success "Servicios detenidos correctamente."
}

# ================================================================
# CLI principal
# ================================================================
case "${1:---start}" in
  --start) start_services ;;
  --stop) stop_services ;;
  *) echo -e "${YELLOW}Uso:${RESET} $0 [--start | --stop]" ;;
esac
