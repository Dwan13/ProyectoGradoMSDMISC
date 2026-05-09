#!/bin/bash
set -e

# Construye la imagen de data-service
cd RealisticServices/data-service

echo "Construyendo imagen Docker..."
docker build -t localhost:32000/mubench/data-service:v1 .

echo "Pusheando imagen al registry local..."
docker push localhost:32000/mubench/data-service:v1

cd ../../..

echo "Reiniciando deployment en Kubernetes..."
kubectl rollout restart deployment data-service -n realistic

echo "Esperando a que el pod esté listo..."
kubectl wait --for=condition=ready pod -l app=data-service -n realistic --timeout=120s

echo "Probando endpoint /metrics..."
curl -s http://localhost:30082/metrics | head -20

echo "Listo. Si ves métricas arriba, Prometheus podrá recolectarlas."
