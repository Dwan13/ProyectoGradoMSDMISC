#!/bin/bash
set -e

# 1. Elimina la imagen local y del registry (ignora error si no existe)
echo "Eliminando imagen local..."
docker rmi localhost:32000/mubench/data-service:v1 || true

echo "Reconstruyendo imagen SIN caché..."
docker build --no-cache -t localhost:32000/mubench/data-service:v1 RealisticServices/data-service

echo "Pusheando imagen al registry..."
docker push localhost:32000/mubench/data-service:v1

# 2. Borra el pod para forzar pull de la nueva imagen
echo "Eliminando pod actual de data-service..."
kubectl delete pod -l app=data-service -n realistic || true

echo "Esperando a que el nuevo pod esté Running..."
kubectl wait --for=condition=Ready pod -l app=data-service -n realistic --timeout=120s

# 3. Prueba el endpoint /metrics
echo "Probando /metrics en NodePort 30082..."
curl -s http://localhost:30082/metrics | head -20
