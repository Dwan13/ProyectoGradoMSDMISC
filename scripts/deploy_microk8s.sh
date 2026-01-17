#!/bin/bash
# ================================================================
# 🚀 Proyecto MuBench - Despliegue Automático en MicroK8s
# ================================================================
# Autor: Dwan13
# Descripción: Despliega, configura y gestiona el entorno completo
# de muBench con observabilidad (Prometheus + Grafana + Dashboard)
# ================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Variables ---
PROJECT_DIR="${HOME}/muBench"
SIMULATION_DIR="${PROJECT_DIR}/WorkModelGenerator/SimulationWorkspace"
CONFIG_DIR="${PROJECT_DIR}/Configs"
MONITORING_DIR="${PROJECT_DIR}/Monitoring"
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
    READY=$(microk8s kubectl get pods -n default 2>/dev/null | grep -E 's0|s1|sdb1' | grep -c "Running" || true)
    (( READY >= 3 )) && { success "Pods de muBench listos."; return 0; }
    sleep 5
  done
  warn "Algunos pods no están completamente listos. Continuando..."
}
enable_dashboard() {
  log "🧩 Verificando Kubernetes Dashboard..."

  # 1. Habilitar si no está activo
  if ! microk8s status --wait-ready | grep -q "dashboard: enabled"; then
    log "🔧 Habilitando dashboard..."
    sudo microk8s enable dashboard || warn "No se pudo habilitar el dashboard automáticamente."
  fi

  # 2. Habilitar RBAC
  log "🔐 Verificando RBAC..."
  sudo microk8s enable rbac || true

  # 3. Crear cuenta de servicio con permisos administrativos
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

  # 4. Esperar a que el Dashboard esté activo
  log "⏳ Esperando que el pod del dashboard esté 'Running'..."
  for _ in {1..30}; do
    STATUS=$(sudo microk8s kubectl get pods -n kube-system -l k8s-app=kubernetes-dashboard -o jsonpath="{.items[0].status.phase}" 2>/dev/null || true)
    [[ "$STATUS" == "Running" ]] && break
    sleep 5
  done

  # 5. Hacer port-forward solo si el puerto está libre
  if ! sudo lsof -i:10443 >/dev/null 2>&1; then
    log "🔌 Iniciando port-forward de Dashboard (puerto 10443)..."
    nohup sudo microk8s kubectl port-forward -n kube-system service/kubernetes-dashboard 10443:443 >"$DASH_LOG" 2>&1 &
    sleep 5
  else
    warn "El puerto 10443 ya está ocupado. Saltando port-forward."
  fi

  success "✅ Dashboard disponible en: https://localhost:10443"

  # 6. Obtener token limpio
  DASH_TOKEN=$(sudo microk8s kubectl -n kube-system create token dashboard-admin 2>/dev/null || true)

  if [[ -z "$DASH_TOKEN" ]]; then
    warn "⚠️ No se pudo crear el token automáticamente."
    echo "Ejecuta manualmente:"
    echo "   sudo microk8s kubectl -n kube-system create token dashboard-admin"
  fi

  echo "$DASH_TOKEN"
}


# ================================================================
# 🚀 Inicio de servicios
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

  mkdir -p "${SIMULATION_DIR}" "${MONITORING_DIR}"

  log "Ejecutando AutoPilot de muBench..."
  cd "${PROJECT_DIR}/Autopilots/K8sAutopilot"
  python3 K8sAutopilot.py -c "${CONFIG_DIR}/K8sAutopilotConf.json"
  success "Modelo y despliegue generados correctamente."

  log "Activando observabilidad..."
  sudo microk8s enable observability || true

  if [[ -f "${MONITORING_DIR}/mubench-servicemonitor.yaml" ]]; then
    log "Aplicando ServiceMonitor personalizado..."
    microk8s kubectl apply -f "${MONITORING_DIR}/mubench-servicemonitor.yaml"
  else
    warn "No se encontró ${MONITORING_DIR}/mubench-servicemonitor.yaml"
  fi

  wait_for_pods

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
  --start)
    start_services
    ;;
  --stop)
    stop_services
    ;;
  *)
    echo -e "${YELLOW}Uso:${RESET} $0 [--start | --stop]"
    ;;
esac
