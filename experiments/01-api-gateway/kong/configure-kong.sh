#!/bin/bash
#
# Configure Kong: Routes, Services, Plugins
#

set -e

echo "════════════════════════════════════════════════════════"
echo "  Kong Configuration: Routes & Plugins                   "
echo "════════════════════════════════════════════════════════"

KONG_ADMIN="http://localhost:30081"

# Verificar Kong Admin API está accesible
echo "✓ Verificando Kong Admin API..."
if ! curl -s "${KONG_ADMIN}/status" | grep -q "database"; then
  echo "❌ Kong Admin API no accesible en ${KONG_ADMIN}"
  exit 1
fi

echo "✓ Kong Admin API OK"

# Crear Service apuntando a backend s0
echo "✓ Creando Kong Service 's0-service'..."
curl -i -X POST "${KONG_ADMIN}/services" \
  --data "name=s0-service" \
  --data "url=http://s0.default.svc.cluster.local:80"

# Crear Route para el servicio
echo "✓ Creando Kong Route '/s0'..."
SERVICE_ID=$(curl -s "${KONG_ADMIN}/services/s0-service" | jq -r '.id')

curl -i -X POST "${KONG_ADMIN}/services/${SERVICE_ID}/routes" \
  --data "paths[]=/s0" \
  --data "name=s0-route"

ROUTE_ID=$(curl -s "${KONG_ADMIN}/routes" | jq -r '.data[] | select(.name=="s0-route") | .id')

# Plugin 1: Rate Limiting (100 req/s)
echo "✓ Configurando Rate Limiting Plugin (100 req/s)..."
curl -i -X POST "${KONG_ADMIN}/routes/${ROUTE_ID}/plugins" \
  --data "name=rate-limiting" \
  --data "config.second=100" \
  --data "config.policy=local" \
  --data "config.fault_tolerant=true"

# Plugin 2: Key Authentication
echo "✓ Configurando Key Auth Plugin..."
curl -i -X POST "${KONG_ADMIN}/routes/${ROUTE_ID}/plugins" \
  --data "name=key-auth" \
  --data "config.key_names[]=apikey"

# Crear Consumer con API Key
echo "✓ Creando Consumer 'test-user'..."
curl -i -X POST "${KONG_ADMIN}/consumers" \
  --data "username=test-user"

curl -i -X POST "${KONG_ADMIN}/consumers/test-user/key-auth" \
  --data "key=test-key-12345"

# Plugin 3: Request Transformer (agregar headers)
echo "✓ Configurando Request Transformer..."
curl -i -X POST "${KONG_ADMIN}/routes/${ROUTE_ID}/plugins" \
  --data "name=request-transformer" \
  --data "config.add.headers[]=X-Gateway:Kong" \
  --data "config.add.headers[]=X-Forwarded-By:API-Gateway"

# Plugin 4: Prometheus (exportar métricas)
echo "✓ Configurando Prometheus Plugin..."
curl -i -X POST "${KONG_ADMIN}/plugins" \
  --data "name=prometheus"

# Verificar configuración
echo ""
echo "✓ Verificando configuración..."
echo "Services:"
curl -s "${KONG_ADMIN}/services" | jq '.data[] | {name, host, port}'

echo ""
echo "Routes:"
curl -s "${KONG_ADMIN}/routes" | jq '.data[] | {name, paths}'

echo ""
echo "Plugins:"
curl -s "${KONG_ADMIN}/plugins" | jq '.data[] | {name, route_id}'

# Test de conectividad
echo ""
echo "✓ Test de conectividad..."
echo "  Con API Key (debe funcionar):"
curl -s -X POST http://localhost:30080/s0/process \
  -H "apikey: test-key-12345" \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

echo ""
echo "  Sin API Key (debe fallar con 401):"
curl -s -X POST http://localhost:30080/s0/process \
  -H "Content-Type: application/json" \
  -d '{}'

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Kong Configurado Exitosamente                       "
echo "════════════════════════════════════════════════════════"
echo "Endpoint: http://localhost:30080/s0/process"
echo "API Key: test-key-12345"
echo "Header: apikey: test-key-12345"
echo ""
echo "Test k6:"
echo "  k6 run -e TARGET_URL=http://localhost:30080/s0 \\"
echo "    -e API_KEY=test-key-12345 \\"
echo "    -e VUS=10 -e DURATION=5m ../tests/test-kong.js"
echo "════════════════════════════════════════════════════════"
