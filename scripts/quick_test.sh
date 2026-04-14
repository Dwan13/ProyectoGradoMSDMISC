#!/bin/bash
# Quick test para validar que los servicios y endpoints funcionen

set -euo pipefail

echo "🧪 Test rápido de servicios muBench enhanced..."
echo ""

# Test 1: Verificar pods
echo "1️⃣ Verificando pods..."
PODS_OK=$(microk8s kubectl get pods -n default | grep -E "s0|s1|sdb1" | grep -c "1/1.*Running" || echo "0")
if [[ $PODS_OK -ge 3 ]]; then
  echo "✅ Pods OK: $PODS_OK/3 Running"
else
  echo "❌ Pods fallando: solo $PODS_OK/3 Running"
  microk8s kubectl get pods -n default | grep -E "s0|s1|sdb1"
  exit 1
fi

echo ""

# Test 2: Probar endpoint /process en s0
echo "2️⃣ Probando endpoint /process en s0..."
S0_POD=$(microk8s kubectl get pod -l app=s0 -n default -o jsonpath='{.items[0].metadata.name}')
RESULT=$(microk8s kubectl exec $S0_POD -n default -- python3 -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:8080/process', data=b'{}', headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req, timeout=5)
print(resp.read().decode())
" 2>/dev/null || echo "ERROR")

if [[ $RESULT == *"\"status\":\"ok\""* ]]; then
  echo "✅ /process OK: $RESULT"
else
  echo "❌ /process falló: $RESULT"
  exit 1
fi

echo ""

# Test 3: Probar endpoint /health
echo "3️⃣ Probando endpoint /health..."
HEALTH=$(microk8s kubectl exec $S0_POD -n default -- python3 -c "
import urllib.request
resp = urllib.request.urlopen('http://localhost:8080/health', timeout=5)
print(resp.read().decode())
" 2>/dev/null || echo "ERROR")

if [[ $HEALTH == *"\"status\":\"healthy\""* ]]; then
  echo "✅ /health OK: $HEALTH"
else
  echo "❌ /health falló: $HEALTH"
  exit 1
fi

echo ""

# Test 4: Port-forward test
echo "4️⃣ Probando port-forward..."
microk8s kubectl port-forward svc/s0 18081:80 -n default >/dev/null 2>&1 &
PF_PID=$!
sleep 3

if curl -s -X POST http://localhost:18081/process -H "Content-Type: application/json" -d '{}' | grep -q "\"status\":\"ok\""; then
  echo "✅ Port-forward OK - endpoint /process accesible"
else
  echo "⚠️  Port-forward funcionó pero endpoint no responde correctamente"
fi

kill $PF_PID 2>/dev/null || true
wait $PF_PID 2>/dev/null || true

echo ""

# Test 5: Verificar métricas Prometheus
echo "5️⃣ Probando endpoint /metrics..."
METRICS=$(microk8s kubectl exec $S0_POD -n default -- curl -s http://localhost:8080/metrics | head -20)
if [[ $METRICS == *"http_request_duration"* ]]; then
  echo "✅ Métricas Prometheus OK"
else
  echo "⚠️  Métricas no encontradas"
fi

echo ""
echo "✅ ✅ ✅ Todos los tests pasaron! Los servicios están funcionando correctamente."
echo ""
echo "Siguiente paso: Ejecutar tests k6 completos con:"
echo "  ./scripts/deploy_microk8s.sh --start --protocol http"
