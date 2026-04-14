#!/bin/bash
#
# Deploy Baseline: Servicio s0 expuesto vía NodePort sin Gateway
#

set -e

echo "═══════════════════════════════════════════════════════"
echo "  Baseline: Despliegue sin API Gateway (NodePort)      "
echo "═══════════════════════════════════════════════════════"

# Verificar que servicios básicos estén corriendo
echo "✓ Verificando servicios s0, s1, sdb1..."
if ! microk8s kubectl get pods -l app=s0 -n default | grep -q Running; then
  echo "❌ Servicio s0 no está corriendo. Desplegar primero:"
  echo "   ./scripts/quick_deploy_services.sh http"
  exit 1
fi

echo "✓ Servicios están  corriendo"

# Cambiar Service s0 a NodePort
echo "✓ Cambiando Service s0 a NodePort..."

cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: s0
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
    protocol: TCP
    name: http
  selector:
    app: s0
EOF

echo "✓ Service s0 ahora accesible en NodePort 30080"

# Esperar a que esté listo
echo "✓ Esperando a que pods estén listos..."
microk8s kubectl wait --for=condition=ready pod -l app=s0 -n default --timeout=60s

# Test rápido
echo "✓ Test rápido de conectividad..."
if curl -s -X POST http://localhost:30080/process \
  -H "Content-Type: application/json" \
  -d '{}' | grep -q "status":"ok"; then
  echo "✅ Baseline desplegado correctamente"
else
  echo "⚠️  Warning: Endpoint no responde correctamente"
fi

# Mostrar info
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  📊 Información del Despliegue"
echo "═══════════════════════════════════════════════════════"
echo "Tipo: Baseline (Sin Gateway)"
echo "Endpoint: http://localhost:30080/process"
echo "Método: POST"
echo "Headers: Content-Type: application/json"
echo "Body: {}"
echo ""
echo "Test k6:"
echo "  k6 run -e TARGET_URL=http://localhost:30080/process \\"
echo "    -e VUS=10 -e DURATION=5m tests/baseline.js"
echo "═══════════════════════════════════════════════════════"
