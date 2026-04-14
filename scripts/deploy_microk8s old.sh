#!/bin/bash
set -e

echo "============================================================"
echo " 🚀 Proyecto MuBench - Despliegue automático en MicroK8s"
echo "============================================================"

# --- Variables base ---
PROJECT_DIR=~/muBench
SIMULATION_DIR=$PROJECT_DIR/WorkModelGenerator/SimulationWorkspace
CONFIG_DIR=$PROJECT_DIR/Configs
MONITORING_DIR=$PROJECT_DIR/Monitoring
NAMESPACE=mubench

echo "📁 Usando carpeta del proyecto: $PROJECT_DIR"
echo "📁 Carpeta SimulationWorkspace: $SIMULATION_DIR"
echo

# --- Validar MicroK8s ---
if ! command -v microk8s &> /dev/null; then
  echo "❌ MicroK8s no está instalado. Instálalo con:"
  echo "   sudo snap install microk8s --classic"
  exit 1
fi

# --- Actualizar dependencias ---
echo "🔧 Actualizando sistema..."
sudo apt update -y && sudo apt upgrade -y

# --- Habilitar Addons principales ---
echo "⚙️ Habilitando MicroK8s addons..."
sudo microk8s enable dns storage dashboard helm3 metrics-server prometheus grafana

# --- Crear namespace ---
echo "🧱 Verificando namespace '$NAMESPACE'..."
sudo microk8s kubectl get namespace $NAMESPACE >/dev/null 2>&1 || \
sudo microk8s kubectl create namespace $NAMESPACE

# --- Instalar dependencias Python ---
echo "🐍 Instalando dependencias Python..."
pip install -q argcomplete python-igraph==0.10.6 pycairo kubernetes google-auth

# --- Verificar estructura de carpetas ---
mkdir -p $SIMULATION_DIR
mkdir -p $MONITORING_DIR

# --- Ejecutar AutoPilot ---
echo "⚙️ Ejecutando muBench AutoPilot..."
cd $PROJECT_DIR/Autopilots/K8sAutopilot
python3 K8sAutopilot.py -c $CONFIG_DIR/K8sAutopilotConf.json

echo "✅ Modelo y despliegue generados correctamente."

# --- Configurar Observabilidad ---
echo "📈 Activando observabilidad..."
sudo microk8s enable observability

# --- Aplicar ServiceMonitor si existe ---
if [ -f "$MONITORING_DIR/mubench-servicemonitor.yaml" ]; then
  echo "🧩 Aplicando ServiceMonitor personalizado..."
  sudo microk8s kubectl apply -f $MONITORING_DIR/mubench-servicemonitor.yaml
else
  echo "⚠️ No se encontró $MONITORING_DIR/mubench-servicemonitor.yaml"
fi

# --- Mostrar servicios activos ---
echo "🌐 Servicios activos:"
sudo microk8s kubectl get svc -A

# --- Instrucciones finales ---
echo
echo "============================================================"
echo " 🎛️  ACCESO A GRAFANA Y PROMETHEUS"
echo "============================================================"
echo "1️⃣  Prometheus: Ejecuta ->"
echo "    sudo microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090"
echo "    y abre http://localhost:9090"
echo
echo "2️⃣  Grafana: Ejecuta ->"
echo "    sudo microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80"
echo "    y abre http://localhost:3000"
echo
echo "   Usuario: admin"
echo "   Contraseña:"
echo "   sudo microk8s kubectl get secret -n observability kube-prom-stack-grafana -o jsonpath=\"{.data.admin-password}\" | base64 --decode; echo"
echo
echo "3️⃣  Dashboard personalizado: importa tu JSON desde"
echo "   $MONITORING_DIR/kubernetes-full-monitoring/mubench_dashboard.json"
echo
echo "============================================================"
echo " ✅ Despliegue completo de MuBench finalizado con éxito."
echo "============================================================"


#!/bin/bash

# ========================
#  muBench MicroK8s Setup
# ========================
# Autor: Dwan13
# Descripción: despliega todo el entorno de muBench con observabilidad y port-forward automáticos.

set -e

PROM_LOG="/tmp/prometheus_portforward.log"
GRAFANA_LOG="/tmp/grafana_portforward.log"

start_services() {
  echo "🚀 Iniciando entorno muBench..."

  # Habilitar los add-ons necesarios
  echo "🔧 Activando complementos de MicroK8s..."
  sudo microk8s enable dns storage dashboard helm3 metrics-server prometheus grafana || true

  # Crear namespace si no existe
  sudo microk8s kubectl get ns mubench >/dev/null 2>&1 || sudo microk8s kubectl create ns mubench

  # Desplegar modelo y servicios
  echo "📦 Desplegando modelo muBench..."
  cd ~/muBench/Autopilots/K8sAutopilot
  python3 K8sAutopilot.py -c ../../Configs/K8sAutopilotConf.json

  echo "✅ Servicios de muBench desplegados."

  # Aplicar ServiceMonitor
  if [ -f "../../Monitoring/mubench-servicemonitor.yaml" ]; then
    sudo microk8s kubectl apply -f ../../Monitoring/mubench-servicemonitor.yaml
    echo "📡 ServiceMonitor aplicado."
  else
    echo "⚠️  No se encontró el archivo mubench-servicemonitor.yaml."
  fi

  # Port-forward automático
  echo "🔌 Iniciando port-forward de Prometheus y Grafana..."

  if ! lsof -i:9090 >/dev/null 2>&1; then
    nohup microk8s kubectl port-forward -n observability svc/kube-prom-stack-kube-prome-prometheus 9090:9090 > $PROM_LOG 2>&1 &
    echo "📡 Prometheus disponible en http://localhost:9090"
  else
    echo "✅ Prometheus ya está activo."
  fi

  if ! lsof -i:3000 >/dev/null 2>&1; then
    nohup sudo microk8s kubectl port-forward -n observability svc/kube-prom-stack-grafana 3000:80 > $GRAFANA_LOG 2>&1 &
    echo "📊 Grafana disponible en http://localhost:3000"
  else
    echo "✅ Grafana ya está activo."
  fi

  echo "📄 Logs de Prometheus: $PROM_LOG"
  echo "📄 Logs de Grafana: $GRAFANA_LOG"

  echo "🎉 muBench está completamente desplegado y listo."
}

stop_services() {
  echo "🛑 Deteniendo port-forward de Prometheus y Grafana..."

  # Detener procesos activos
  sudo pkill -f "port-forward -n observability svc/prometheus-kube-prom-stack-kube-prome-prometheus" || true
  sudo pkill -f "port-forward -n observability svc/kube-prom-stack-grafana" || true

  echo "🧹 Limpiando logs temporales..."
  rm -f $PROM_LOG $GRAFANA_LOG

  echo "✅ Port-forwards detenidos correctamente."
}

# =========================================
#  CLI principal
# =========================================

case "$1" in
  --start|"")
    start_services
    ;;
  --stop)
    stop_services
    ;;
  *)
    echo "Uso: $0 [--start | --stop]"
    ;;
esac

