#!/bin/bash
# ================================================================
# 🚀 Proyecto MuBench - Despliegue Automático en MicroK8s + k6
# ================================================================
# Autor: Dwan13
# Descripción: Despliega, configura y gestiona el entorno completo
# de muBench con observabilidad (Prometheus + Grafana + Dashboard)
# y pruebas automáticas de rendimiento con k6.
# 
# Soporta comunicación HTTP/HTTPS entre microservicios para medir
# latencia, throughput y overhead de TLS.
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
TLS_DIR="${PROJECT_DIR}/tls-certs"
NAMESPACE="default"

# Protocol selection (http or https)
COMM_PROTOCOL="${COMM_PROTOCOL:-http}"

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

generate_tls_certificates() {
  if [[ "$COMM_PROTOCOL" != "https" ]]; then
    return 0
  fi

  log "🔐 Generando certificados TLS auto-firmados..."
  mkdir -p "${TLS_DIR}"

  for SERVICE in s0 s1 sdb1; do
    if [[ -f "${TLS_DIR}/${SERVICE}-cert.pem" ]]; then
      log "Certificado para ${SERVICE} ya existe, omitiendo..."
      continue
    fi

    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${TLS_DIR}/${SERVICE}-key.pem" \
      -out "${TLS_DIR}/${SERVICE}-cert.pem" \
      -days 365 \
      -subj "/CN=${SERVICE}.${NAMESPACE}.svc.cluster.local/O=muBench/C=US" \
      >/dev/null 2>&1

    success "Certificado generado para ${SERVICE}"
  done

  # Crear secrets en Kubernetes
  for SERVICE in s0 s1 sdb1; do
    if microk8s kubectl get secret ${SERVICE}-tls-secret -n ${NAMESPACE} >/dev/null 2>&1; then
      log "Secret ${SERVICE}-tls-secret ya existe, omitiendo..."
      continue
    fi

    microk8s kubectl create secret tls ${SERVICE}-tls-secret \
      --cert="${TLS_DIR}/${SERVICE}-cert.pem" \
      --key="${TLS_DIR}/${SERVICE}-key.pem" \
      -n ${NAMESPACE} >/dev/null 2>&1

    success "Secret TLS creado para ${SERVICE}"
  done
}

wait_for_pods() {
  log "Esperando a que los pods de muBench estén corriendo..."
  for _ in {1..30}; do
    READY=$(microk8s kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E 's0|s1|sdb1|gw-nginx' | grep -c "Running" || true)
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
# 🧪 k6 Tests
# ================================================================
check_k6() {
  log "Verificando instalación de k6..."
  
  if command -v k6 >/dev/null 2>&1; then
    success "✅ k6 detectado correctamente."
    k6 version
    return 0
  fi
  
  warn "k6 no encontrado. Instalando..."
  
  # Detectar OS y instalar
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo gpg -k >/dev/null 2>&1 || { error "gpg no encontrado"; }
    sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
      --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 || true
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
      sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install -y k6
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install k6
  else
    error "OS no soportado para instalación automática de k6. Instálalo manualmente desde https://k6.io/docs/get-started/installation/"
  fi
  
  success "✅ k6 instalado correctamente."
}

run_k6_tests() {
  check_k6

  mkdir -p "${RESULTS_DIR}"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  
  # Usar port-forward para acceder a los servicios
  LOCAL_PORT=8081
  
  log "🔌 Iniciando port-forward a servicio s0..."
  microk8s kubectl port-forward svc/s0 ${LOCAL_PORT}:80 -n ${NAMESPACE} > /tmp/k6_portforward.log 2>&1 &
  PF_PID=$!
  sleep 3
  
  # Verificar que port-forward esté funcionando
  if ! ps -p $PF_PID > /dev/null; then
    warn "❌ Port-forward falló, intentando con gw-nginx..."
    GW_PORT=$(microk8s kubectl get svc gw-nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "31113")
    TARGET_URL="http://127.0.0.1:${GW_PORT}/s0"
  else
    TARGET_URL="http://127.0.0.1:${LOCAL_PORT}/process"
  fi

  log "🏁 Ejecutando k6 contra ${TARGET_URL}"
  log "Protocolo de comunicación inter-servicio: ${COMM_PROTOCOL}"

  # Test baseline
  RESULT_FILE="${RESULTS_DIR}/${COMM_PROTOCOL}-baseline-${TIMESTAMP}.json"
  
  k6 run --out json="${RESULT_FILE}" \
    -e TARGET_URL="${TARGET_URL}" \
    -e VUS=20 \
    -e DURATION=60s \
    -e PROTOCOL="${COMM_PROTOCOL}" \
    -e INSECURE_SKIP_TLS_VERIFY=true \
    "${TEST_DIR}/baseline.js" || warn "⚠️ Error al ejecutar prueba k6 baseline"

  success "✅ Prueba baseline completada. Resultados en: ${RESULT_FILE}"

  # Test inter-service communication
  RESULT_FILE_INTER="${RESULTS_DIR}/${COMM_PROTOCOL}-interservice-${TIMESTAMP}.json"
  
  log "🔗 Ejecutando prueba de comunicación inter-servicio..."
  
  # Para inter-service test, usar base URL sin endpoint
  BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
  if ! ps -p ${PF_PID:-0} > /dev/null 2>&1; then
    BASE_URL="http://127.0.0.1:${GW_PORT}"
  fi
  
  k6 run --out json="${RESULT_FILE_INTER}" \
    -e TARGET_URL="${BASE_URL}" \
    -e VUS=20 \
    -e DURATION=60s \
    -e PROTOCOL="${COMM_PROTOCOL}" \
    -e INSECURE_SKIP_TLS_VERIFY=true \
    "${TEST_DIR}/inter-service-test.js" || warn "⚠️ Error al ejecutar prueba inter-servicio"

  success "✅ Prueba inter-servicio completada. Resultados en: ${RESULT_FILE_INTER}"

  # Cleanup port-forward
  if [[ -n "${PF_PID:-}" ]] && ps -p $PF_PID > /dev/null 2>&1; then
    log "🔌 Cerrando port-forward..."
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
  fi

  # Summary
  log "📊 Resumen de resultados:"
  echo "  Baseline:      ${RESULT_FILE}"
  echo "  Inter-service: ${RESULT_FILE_INTER}"
  echo ""
  echo "Analizar con: cat ${RESULT_FILE} | jq '.metrics'"
}

create_grafana_dashboard() {
  log "🔧 Creando dashboards en Grafana..."

  GRAFANA_URL="http://localhost:3000"
  GRAFANA_USER="admin"
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo "")

  [[ -z "$GRAFANA_PASS" ]] && { warn "No se pudo obtener contraseña de Grafana"; return; }

  # Wait for Grafana to be ready
  for _ in {1..10}; do
    if curl -s "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  DASHBOARD_JSON=$(cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "mubench-microservices",
    "title": "MuBench Microservices Performance",
    "tags": ["mubench", "microservices", "k6"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "refresh": "5s",
    "panels": [
      {
        "id": 1,
        "type": "graph",
        "title": "HTTP Request Duration (P95)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))",
            "legendFormat": "{{service}} - {{endpoint}}"
          }
        ],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
        "yaxes": [{"format": "s"}]
      },
      {
        "id": 2,
        "type": "graph",
        "title": "Throughput (requests/sec)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[1m])) by (service)",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
        "yaxes": [{"format": "reqps"}]
      },
      {
        "id": 3,
        "type": "graph",
        "title": "Network TX Bytes",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(container_network_transmit_bytes_total{namespace=\"default\"}[1m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
        "yaxes": [{"format": "Bps"}]
      },
      {
        "id": 4,
        "type": "graph",
        "title": "Network RX Bytes",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(container_network_receive_bytes_total{namespace=\"default\"}[1m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8},
        "yaxes": [{"format": "Bps"}]
      },
      {
        "id": 5,
        "type": "stat",
        "title": "Error Rate",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status_code=~\"5..\"}[1m])) / sum(rate(http_requests_total[1m]))"
          }
        ],
        "gridPos": {"x": 0, "y": 16, "w": 6, "h": 4}
      },
      {
        "id": 6,
        "type": "stat",
        "title": "Total Requests/sec",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[1m]))"
          }
        ],
        "gridPos": {"x": 6, "y": 16, "w": 6, "h": 4}
      }
    ]
  },
  "overwrite": true
}
EOF
)

  curl -s -X POST -H "Content-Type: application/json" \
       -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
       -d "${DASHBOARD_JSON}" \
       "${GRAFANA_URL}/api/dashboards/db" >/dev/null || warn "No se pudo crear dashboard en Grafana"

  success "✅ Dashboard 'MuBench Microservices Performance' creado en Grafana: ${GRAFANA_URL}"
}

# ================================================================
# 🚀 Inicio de servicios
# ================================================================
start_services() {
  log "Iniciando despliegue automatizado MuBench..."
  log "Protocolo de comunicación: ${COMM_PROTOCOL}"
  
  microk8s status --wait-ready >/dev/null 2>&1 || error "❌ MicroK8s no está listo"

  # Generate TLS certificates if HTTPS mode
  generate_tls_certificates

  wait_for_pods
  fix_nginx_dns

  log "Iniciando port-forward Prometheus y Grafana..."
  pkill -f "port-forward.*prometheus" || true
  pkill -f "port-forward.*grafana" || true
  
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >"$PROM_LOG" 2>&1 &
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 >"$GRAFANA_LOG" 2>&1 &
  
  sleep 5
  
  log "Configurando Dashboard de Kubernetes..."
  DASH_TOKEN=$(enable_dashboard || true)

  run_k6_tests
  create_grafana_dashboard

  log "Obteniendo credenciales..."
  GRAFANA_PASS=$(microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo "N/A")

  {
    echo "============================"
    echo "🧩 MuBench Access Credentials"
    echo "============================"
    echo
    echo "Communication Protocol: ${COMM_PROTOCOL^^}"
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
    echo
    echo "Experiments"
    echo "------------"
    echo "HTTP:  ${PROJECT_DIR}/experiments/scenario-http.md"
    echo "HTTPS: ${PROJECT_DIR}/experiments/scenario-https.md"
  } > "${CRED_FILE}"

  chmod 600 "${CRED_FILE}"
  success "Credenciales guardadas en: ${CRED_FILE}"

  success "✅ Despliegue completo. Accesos:"
  echo -e "${CYAN}Grafana:${RESET}     http://localhost:3000"
  echo -e "${CYAN}Prometheus:${RESET}  http://localhost:9090"
  echo -e "${CYAN}Dashboard:${RESET}   https://localhost:10443"
  echo -e "${CYAN}Protocol:${RESET}    ${COMM_PROTOCOL^^}"
  echo ""
  echo -e "${GREEN}Ver experimentos en: ${PROJECT_DIR}/experiments/${RESET}"
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
usage() {
  cat <<EOF
${CYAN}MuBench Deployment Script${RESET}

${GREEN}Usage:${RESET}
  $0 [OPTIONS]

${GREEN}Options:${RESET}
  --start               Iniciar servicios y ejecutar tests
  --stop                Detener port-forwards
  --protocol <http|https>  Configurar protocolo de comunicación (default: http)
  --help                Mostrar esta ayuda

${GREEN}Examples:${RESET}
  # Desplegar con HTTP
  $0 --start --protocol http

  # Desplegar con HTTPS
  COMM_PROTOCOL=https $0 --start

  # Detener servicios
  $0 --stop

${GREEN}Environment Variables:${RESET}
  COMM_PROTOCOL         http | https (default: http)
  VUS                   Virtual users para k6 (default: 20)
  DURATION              Duración de tests k6 (default: 60s)

${GREEN}More Info:${RESET}
  Experiments: ${PROJECT_DIR}/experiments/
  Results:     ${RESULTS_DIR}/
  Credentials: ${CRED_FILE}
EOF
}

# Parse arguments
COMMAND="--start"
while [[ $# -gt 0 ]]; do
  case $1 in
    --start)
      COMMAND="--start"
      shift
      ;;
    --stop)
      COMMAND="--stop"
      shift
      ;;
    --protocol)
      COMM_PROTOCOL="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      warn "Opción desconocida: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate protocol
if [[ "$COMM_PROTOCOL" != "http" && "$COMM_PROTOCOL" != "https" ]]; then
  error "Protocolo inválido: $COMM_PROTOCOL. Usar 'http' o 'https'"
fi

case "${COMMAND}" in
  --start) start_services ;;
  --stop) stop_services ;;
  *) usage ;;
esac
