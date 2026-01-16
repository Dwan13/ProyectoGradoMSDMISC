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
