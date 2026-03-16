#!/bin/bash
#
# Install Kong Gateway usando Helm
#

set -e

echo "════════════════════════════════════════════════════════"
echo "  Kong Gateway Installation                             "
echo "════════════════════════════════════════════════════════"

# Verificar Helm está instalado
if ! command -v helm &> /dev/null; then
  echo "❌ Helm no está instalado. Instalando..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "✓ Helm instalado: $(helm version --short)"

# Agregar repo de Kong
echo "✓ Agregando repositorio de Kong..."
helm repo add kong https://charts.konghq.com
helm repo update

# Crear namespace
echo "✓ Creando namespace kong..."
microk8s kubectl create namespace kong --dry-run=client -o yaml | microk8s kubectl apply -f -

# Instalar Kong con PostgreSQL como backend
echo "✓ Instalando Kong Gateway..."
helm install kong kong/kong \
  --namespace kong \
  --values kong-values.yaml \
  --wait \
  --timeout 10m

echo "✓ Kong instalado exitosamente"

# Esperar a que pods estén listos
echo "✓ Esperando a que Kong esté listo..."
microk8s kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kong \
  -n kong \
  --timeout=300s

# Verificar instalación
echo "✓ Verificando instalación..."
microk8s kubectl get pods -n kong
microk8s kubectl get svc -n kong

# Obtener NodePort de Kong Proxy
KONG_PROXY_PORT=$(microk8s kubectl get svc kong-kong-proxy -n kong \
  -o jsonpath='{.spec.ports[?(@.name=="kong-proxy")].nodePort}')

echo ""
echo "════════════════════════════════════════════════════════"
echo "  📊 Kong Gateway Instalado                             "
echo "════════════════════════════════════════════════════════"
echo "Namespace: kong"
echo "Proxy URL: http://localhost:$KONG_PROXY_PORT"
echo "Admin API: http://localhost:8001"
echo ""
echo "Próximo paso: Configurar rutas y plugins"
echo "  ./configure-kong.sh"
echo "════════════════════════════════════════════════════════"
