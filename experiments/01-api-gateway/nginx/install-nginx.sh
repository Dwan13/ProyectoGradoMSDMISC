#!/bin/bash
#
# Install NGINX Ingress Controller usando microk8s addon
#

set -e

echo "════════════════════════════════════════════════════════"
echo "  NGINX Ingress Controller Installation                 "
echo "════════════════════════════════════════════════════════"

# Habilitar addon de ingress en microk8s
echo "✓ Habilitando NGINX Ingress addon..."
microk8s enable ingress

# Esperar a que el controller esté listo
echo "✓ Esperando a que NGINX Ingress esté listo..."
microk8s kubectl wait --namespace ingress \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=300s

# Verificar instalación
echo "✓ Verificando instalación..."
microk8s kubectl get pods -n ingress
microk8s kubectl get svc -n ingress

# Cambiar Service a NodePort en puerto 30080
echo "✓ Configurando NodePort 30080..."
microk8s kubectl patch svc ingress-nginx-controller -n ingress \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080,"name":"http"}]}}'

# Aplicar ConfigMap con rate limiting
echo "✓ Aplicando ConfigMap para rate limiting..."
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configuration
  namespace: ingress
data:
  # Rate limiting: 100 req/s
  limit-rate: "100"
  limit-rate-after: "0"
  
  # Optimizaciones
  worker-processes: "2"
  max-worker-connections: "8192"
  
  # Logging
  log-format-upstream: '\$remote_addr - \$remote_user [\$time_local] "\$request" \$status \$body_bytes_sent "\$http_referer" "\$http_user_agent" \$request_length \$request_time [\$proxy_upstream_name] \$upstream_addr \$upstream_response_length \$upstream_response_time \$upstream_status'
EOF

# Aplicar Ingress para servicio s0
echo "✓ Creando Ingress para s0..."
microk8s kubectl apply -f ingress-s0.yaml

# Esperar a que Ingress esté configurado
sleep 10

# Verificar Ingress
echo "✓ Verificando Ingress..."
microk8s kubectl get ingress -n default

# Test rápido
echo ""
echo "✓ Test de conectividad..."
if curl -s -X POST http://localhost:30080/s0/process \
  -H "Content-Type: application/json" \
  -d '{}' | grep -q '"status":"ok"'; then
  echo "✅ NGINX Ingress configurado correctamente"
else
  echo "⚠️  Warning: Endpoint no responde correctamente"
  echo "   Revisar logs:"
  echo "   microk8s kubectl logs -n ingress -l app.kubernetes.io/name=ingress-nginx"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  📊 NGINX Ingress Instalado                            "
echo "════════════════════════════════════════════════════════"
echo "Namespace: ingress"
echo "Endpoint: http://localhost:30080/s0/process"
echo "Rate Limit: 100 req/s"
echo ""
echo "Test k6:"
echo "  k6 run -e TARGET_URL=http://localhost:30080/s0 \\"
echo "    -e VUS=10 -e DURATION=5m ../tests/test-nginx.js"
echo "════════════════════════════════════════════════════════"
