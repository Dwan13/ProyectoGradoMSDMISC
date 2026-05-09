#!/usr/bin/env bash
set -euo pipefail

################################################################################
# full-project-setup.sh
#
# Setup completo del proyecto muBench en una máquina con MicroK8s
# Instala todas las dependencias, levanta MicroK8s, despliega servicios realistas
# y configura monitoreo + k6
#
# Uso: bash scripts/full-project-setup.sh [--skip-k8s] [--skip-monitoring]
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
SKIP_K8S=false
SKIP_MONITORING=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-k8s) SKIP_K8S=true; shift ;;
    --skip-monitoring) SKIP_MONITORING=true; shift ;;
    *) shift ;;
  esac
done

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_section() { echo -e "\n${YELLOW}╔════════════════════════════════════════════════════════╗${NC}\n${YELLOW}║${NC} $* \n${YELLOW}╚════════════════════════════════════════════════════════╝${NC}\n"; }

################################################################################
# 1. VERIFICAR PREREQUISITES
################################################################################

log_section "1️⃣  VERIFICANDO PREREQUISITES"

check_command() {
  if ! command -v "$1" &> /dev/null; then
    log_error "$1 no instalado. Instálalo primero."
    return 1
  fi
  log_success "$1 encontrado"
}

check_command "docker"
check_command "python3"
check_command "curl"
check_command "jq"

# Verificar WSL config en Windows
if grep -qi "microsoft" /proc/version 2>/dev/null; then
  log_info "Sistema: WSL detectado"
  if [ -f ~/.wslconfig ]; then
    log_success "~/.wslconfig existe"
    grep -i "memory\|processors" ~/.wslconfig || \
      log_warn "Considera aumentar memory/processors en ~/.wslconfig"
  fi
fi

################################################################################
# 2. INSTALAR/LEVANTAR MICROK8S
################################################################################

if [ "$SKIP_K8S" = false ]; then
  log_section "2️⃣  CONFIGURANDO MICROK8S"
  
  if ! command -v microk8s &> /dev/null; then
    log_info "Instalando MicroK8s..."
    snap install microk8s --classic --channel=1.28/stable
    usermod -a -G microk8s $USER
    log_warn "Usuario agregado a grupo microk8s. Reinicia tu sesión."
  else
    log_success "MicroK8s ya instalado"
  fi
  
  log_info "Esperando MicroK8s ready..."
  microk8s status --wait-ready --timeout=600
  
  log_info "Habilitando add-ons necesarios..."
  microk8s enable dns storage ingress
  
  # Prometheus + Grafana para monitoreo
  if [ "$SKIP_MONITORING" = false ]; then
    microk8s enable prometheus
    log_success "Prometheus habilitado en puerto 30000"
  fi
  
  # Istio (opcional pero recomendado)
  log_info "¿Instalar Istio? (recomendado para C1/C2) [y/N]"
  read -r -t 5 install_istio || install_istio="n"
  if [[ "$install_istio" =~ ^[Yy]$ ]]; then
    microk8s enable istio
    log_success "Istio habilitado"
  fi
else
  log_success "Saltando setup de K8s (--skip-k8s)"
fi

################################################################################
# 3. CREAR NAMESPACES Y CONFIGURACIONES
################################################################################

log_section "3️⃣  CREANDO NAMESPACES Y CONFIGURACIONES"

alias kubectl="microk8s kubectl"

# Namespace para experimentos realistas
kubectl create namespace realistic --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace 'realistic' listo"

# TLS certificate para Istio (requerido)
if kubectl get secret mubench-tls -n istio-system &>/dev/null 2>&1; then
  log_success "Certificado TLS ya existe"
else
  log_info "Generando certificado TLS autofirmado..."
  openssl req -x509 -newkey rsa:4096 -keyout /tmp/tls.key -out /tmp/tls.crt \
    -days 365 -nodes -subj "/CN=realistic.local" 2>/dev/null
  kubectl create secret tls mubench-tls -n istio-system \
    --cert=/tmp/tls.crt --key=/tmp/tls.key --dry-run=client -o yaml | kubectl apply -f -
  log_success "Certificado TLS creado"
  rm -f /tmp/tls.key /tmp/tls.crt
fi

################################################################################
# 4. CONSTRUIR IMAGENES DOCKER
################################################################################

log_section "4️⃣  CONSTRUYENDO IMÁGENES DOCKER"

# Asegurarse de usar Docker del host (no contenedor)
eval "$(microk8s docker-env)"

cd "$ROOT_DIR"

# Servicios realistas
for service in auth-service api-service data-service; do
  service_path="$ROOT_DIR/RealisticServices/$service"
  if [ -d "$service_path" ]; then
    log_info "Construyendo $service..."
    docker build -t "mubench/$service:latest" "$service_path"
    log_success "$service construido"
  fi
done

# Service Cell (si existe)
if [ -d "$ROOT_DIR/ServiceCell" ]; then
  log_info "Construyendo ServiceCell..."
  docker build -t mubench/service-cell:latest "$ROOT_DIR/ServiceCell"
  log_success "ServiceCell construido"
fi

################################################################################
# 5. DESPLEGAR SERVICIOS BASE
################################################################################

log_section "5️⃣  DESPLEGANDO SERVICIOS REALISTAS"

log_info "Aplicando manifiestos base..."

if [ -f "$ROOT_DIR/RealisticServices/k8s/02-services.yaml" ]; then
  kubectl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services.yaml"
  log_success "Servicios base desplegados"
else
  log_error "Manifiesto base no encontrado"
fi

log_info "Esperando que los servicios estén Ready..."
for dep in auth-service api-service data-service; do
  kubectl rollout status deployment/"$dep" -n realistic --timeout=300s
done

log_success "Servicios realistas listos"

################################################################################
# 6. INSTALAR K6
################################################################################

log_section "6️⃣  INSTALANDO K6 PARA GENERACIÓN DE CARGA"

if ! command -v k6 &> /dev/null; then
  log_info "Instalando k6..."
  
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
    sudo add-apt-repository "deb https://dl.k6.io/deb releases main"
    sudo apt-get update && sudo apt-get install -y k6
  elif command -v brew &> /dev/null; then
    brew install k6
  else
    log_warn "No se pudo instalar k6 automáticamente. Instálalo desde https://k6.io/docs/get-started/installation/"
  fi
  
  if command -v k6 &> /dev/null; then
    log_success "k6 instalado: $(k6 version)"
  fi
else
  log_success "k6 ya instalado: $(k6 version)"
fi

################################################################################
# 7. CREAR DIRECTORIOS DE RESULTADOS
################################################################################

log_section "7️⃣  PREPARANDO DIRECTORIOS"

mkdir -p "$ROOT_DIR/Testing/results/auto_runs"
mkdir -p "$ROOT_DIR/Testing/results/scaling_tests"
mkdir -p "$ROOT_DIR/Testing/results/plots"

log_success "Directorios de resultados listos"

################################################################################
# 8. CONFIGURAR KUBECONFIG
################################################################################

log_section "8️⃣  CONFIGURANDO KUBECTL"

# Crear symlink para kubectl local
if [ ! -L /usr/local/bin/kubectl ]; then
  sudo ln -sf "$(which microk8s)" /usr/local/bin/microk8s
  log_success "microk8s symlink creado"
fi

# Guardar kubeconfig para uso local
microk8s config > ~/.kube/config 2>/dev/null || true
chmod 600 ~/.kube/config 2>/dev/null || true

log_success "kubeconfig configurado"

################################################################################
# 9. VERIFICACIÓN FINAL
################################################################################

log_section "9️⃣  VERIFICACIÓN FINAL"

log_info "Estado del cluster:"
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
kubectl get pods -n realistic

log_success "Servicios en 'realistic' namespace:"
kubectl get svc -n realistic

log_info "NodePorts asignados:"
kubectl get svc -n realistic -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].nodePort

################################################################################
# 10. INFORMACIÓN FINAL
################################################################################

log_section "🎉 SETUP COMPLETADO EXITOSAMENTE"

cat << EOF

┌─────────────────────────────────────────────────────────────────────────┐
│                    SIGUIENTES PASOS                                      │
└─────────────────────────────────────────────────────────────────────────┘

1️⃣  Verificar servicios: kubectl get pods -n realistic -w

2️⃣  Ejecutar benchmark (1 VU): 
    bash scripts/run-all-controls-experiments.sh

3️⃣  Ejecutar test escalabilidad (1→5→10→20 VUs):
    bash scripts/run-scaling-tests.sh

4️⃣  Ver resultados:
    ls -la Testing/results/auto_runs/
    ls -la Testing/results/scaling_tests/

5️⃣  Acceder a monitoreo (si está habilitado):
    • Prometheus: http://localhost:30000
    • Grafana:    http://localhost:30001 (admin/prom-operator)

┌─────────────────────────────────────────────────────────────────────────┐
│                    ENDPOINTS DISPONIBLES                                │
└─────────────────────────────────────────────────────────────────────────┘

$(kubectl get svc -n realistic -o custom-columns=NAME:.metadata.name,CLUSTER-IP:.spec.clusterIP,NODEPORT:.spec.ports[0].nodePort --no-headers)

┌─────────────────────────────────────────────────────────────────────────┐
│                    CONFIGURACIÓN VERIFICADA                             │
└─────────────────────────────────────────────────────────────────────────┘

✓ MicroK8s running
✓ Namespaces creados
✓ Servicios desplegados
✓ k6 instalado
✓ Directorios listos

EOF

log_success "¡El proyecto está listo para experimentar!"
