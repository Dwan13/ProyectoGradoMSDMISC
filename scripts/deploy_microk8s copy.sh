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
NAMESPACE="mubench"

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
    READY=$(microk8s kubectl get pods -n default 2>/dev/null | grep -E 's0|s1|sdb1|gw-nginx' | grep -c "Running" || true)
    (( READY >= 3 )) && { success "Pods de muBench listos."; return 0; }
    sleep 5
  done
  warn "Algunos pods no están completamente listos. Continuando..."
}

enable_dashboard() {
  log "🧩 Verificando Kubernetes Dashboard..."

  if ! microk8s status --wait-ready | grep -q "dashboard: enabled"; then
    log "🔧 Habilitando dashboard..."
    sudo microk8s enable dashboard || warn "No se pudo habilitar el dashboard automáticamente."
  fi

  log "🔐 Verificando RBAC..."
  sudo microk8s enable rbac || true

  if ! sudo microk8s kubectl get sa dashboard-admin -n kube-system >/dev/null 2>&1; then
    log "👤 Creando ServiceAccount y ClusterRoleBinding..."
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

  log "⏳ Esperando que el pod del dashboard esté 'Running'..."
  for _ in {1..30}; do
    STATUS=$(sudo microk8s kubectl get pods -n kube-system -l k8s-app=kubernetes-dashboard -o jsonpath="{.items[0].status.phase}" 2>/dev/null || true)
    [[ "$STATUS" == "Running" ]] && break
    sleep 5
  done

  if ! sudo lsof -i:10443 >/dev/null 2>&1; then
    log "🔌 Iniciando port-forward de Dashboard (puerto 10443)..."
    nohup sudo microk8s kubectl port-forward -n kube-system service/kubernetes-dashboard 10443:443 >"$DASH_LOG" 2>&1 &
    sleep 5
  else
    warn "El puerto 10443 ya está ocupado. Saltando port-forward."
  fi

  success "✅ Dashboard disponible en: https://localhost:10443"

  DASH_TOKEN=$(sudo microk8s kubectl -n kube-system create token dashboard-admin 2>/dev/null || true)
  [[ -z "$DASH_TOKEN" ]] && warn "⚠️ No se pudo crear token automáticamente. Ejecuta manualmente: sudo microk8s kubectl -n kube-system create token dashboard-admin"
  echo "$DASH_TOKEN"
}

# ================================================================
# 🧠 Reconfiguración del gateway para demo y servicios simulados
# ================================================================
fix_nginx_dns() {
  log "🔧 Reconfigurando gateway gw-nginx con ruta demo y servicios simulados..."

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
        resolver kube-dns.kube-system.svc.cluster.local valid=10s ipv6=off;

        # --- Ruta demo ---
        location /demo/ {
            rewrite ^/demo/?(.*)\$ /\$1 break;
            proxy_pass http://api-demo.default.svc.cluster.local:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # --- Root ---
        location / {
            proxy_pass http://api-demo.default.svc.cluster.local:80;
        }

        # --- Rutas simuladas ---
        location /service0/ {
            proxy_pass http://s0.default.svc.cluster.local:80;
        }
        location /service1/ {
            proxy_pass http://s1.default.svc.cluster.local:80;
        }
        location /database/ {
            proxy_pass http://sdb1.default.svc.cluster.local:80;
        }
    }
EOF

  sudo microk8s kubectl delete pod -l app=gw-nginx -n default --force --grace-period=0
  success "✅ Configuración de gw-nginx actualizada con soporte para /demo"
}

# ================================================================
# 🧩 Verificar e Instalar Apache JMeter
# ================================================================
check_jmeter() {
  log "Verificando instalación de Apache JMeter..."
  if ! command -v jmeter &>/dev/null; then
    warn "JMeter no está instalado."
    read -p "¿Deseas instalarlo automáticamente? (s/n): " opt
    if [[ "$opt" =~ ^[sS]$ ]]; then
      sudo apt update && sudo apt install -y jmeter
      success "JMeter instalado correctamente."
    else
      error "No se puede ejecutar la prueba sin JMeter."
    fi
  else
    success "JMeter detectado correctamente."
  fi
}

# ================================================================
# 🚀 Inicio de servicios + Prueba de carga
# ================================================================
start_services() {
  echo -e "${GREEN}============================================================${RESET}"
  echo -e "${GREEN} 🚀 Iniciando despliegue automatizado de MuBench${RESET}"
  echo -e "${GREEN}============================================================${RESET}"

  command -v microk8s >/dev/null 2>&1 || error "MicroK8s no está instalado. Instálalo con: sudo snap install microk8s --classic"

  log "Actualizando sistema..."
  sudo apt update -y >/dev/null && sudo apt upgrade -y >/dev/null

  log "Habilitando complementos de MicroK8s..."
  sudo microk8s enable dns storage helm3 metrics-server prometheus grafana || true

  log "Verificando namespace '${NAMESPACE}'..."
  microk8s kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || microk8s kubectl create ns "${NAMESPACE}"

  log "Instalando dependencias de Python..."
  pip install -q --upgrade argcomplete python-igraph==0.10.6 pycairo kubernetes google-auth

  mkdir -p "${SIMULATION_DIR}" "${MONITORING_DIR}" "${RESULTS_DIR}"

  log "Ejecutando AutoPilot de muBench..."
  cd "${PROJECT_DIR}/Autopilots/K8sAutopilot"
  python3 K8sAutopilot.py -c "${CONFIG_DIR}/K8sAutopilotConf.json"
  success "Modelo y despliegue generados correctamente."

  wait_for_pods
  fix_nginx_dns

  log "Iniciando port-forward de Prometheus y Grafana..."
  sudo pkill -f "port-forward -n observability" || true
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 >"${PROM_LOG}" 2>&1 &
  nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 >"${GRAFANA_LOG}" 2>&1 &

  log "Configurando Dashboard de Kubernetes..."
  DASH_TOKEN=$(enable_dashboard || true)

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

  # ================================================================
  # 🧪 EJECUTAR PRUEBA JMETER AUTOMÁTICAMENTE
  # ================================================================
  check_jmeter
  log "Ejecutando prueba de carga JMeter (baseline demo)..."

  GW_PORT=$(microk8s kubectl get svc gw-nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
  GW_IP="127.0.0.1"
  TARGET_URL="http://${GW_IP}:${GW_PORT}/demo/"

  if [[ -z "$GW_PORT" ]]; then
    warn "No se pudo detectar el puerto de gw-nginx. Saltando prueba JMeter."
    return 0
  fi

  log "Verificando conexión con ${TARGET_URL}..."
  if ! curl -s --max-time 5 "${TARGET_URL}" >/dev/null 2>&1; then
    warn "⚠️  El servicio gw-nginx no responde en ${TARGET_URL}. Esperando 10 segundos..."
    sleep 10
  fi

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  RESULT_FILE="${RESULTS_DIR}/results_${TIMESTAMP}.jtl"

  log "🏁 Ejecutando JMeter contra ${TARGET_URL}"
  jmeter -n -t "${TEST_DIR}/mubench_baseline.jmx" \
    -JTARGET_URL="${TARGET_URL}" \
    -JTHREADS=50 \
    -JDURATION=60 \
    -l "${RESULT_FILE}"

  success "✅ Prueba completada. Resultados guardados en:"
  echo "   ${RESULT_FILE}"

  echo
  success "Despliegue completo. Accesos disponibles:"
  echo -e "${CYAN}🔗 Grafana:${RESET}     http://localhost:3000"
  echo -e "${CYAN}🔗 Prometheus:${RESET}  http://localhost:9090"
  echo -e "${CYAN}🔗 Dashboard:${RESET}   https://localhost:10443"
}


# ================================================================
# 🛑 Detener servicios
# ================================================================
stop_services() {
  log "Deteniendo port-forwards y limpiando..."
  sudo pkill -f "port-forward -n observability" || true
  sudo pkill -f "port-forward -n kube-system service/kubernetes-dashboard" || true
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
