#!/bin/bash
set -e

echo "1. ServiceMonitor para data-service:"
kubectl get servicemonitor -A | grep data-service || echo "No hay ServiceMonitor para data-service"

echo "2. Configuración de endpoints en ServiceMonitor:"
kubectl get servicemonitor -n realistic -o yaml | grep -A 20 endpoints || echo "No hay endpoints configurados"

echo "3. Service data-service (puertos, anotaciones, selector):"
kubectl get svc -n realistic -o yaml | grep -A 20 data-service

echo "4. Endpoints asociados al Service data-service:"
kubectl get endpoints -n realistic | grep data-service

echo "5. Detalles completos del ServiceMonitor para data-service:"
kubectl -n realistic describe servicemonitor | grep -A 30 data-service

echo "6. Configuración completa de todos los ServiceMonitor en realistic:"
kubectl -n realistic get servicemonitor -o yaml

echo "7. Estado del pod de Prometheus en realistic:"
kubectl -n realistic get pod -l app=prometheus -o wide

echo "8. Últimos logs de Prometheus:"
kubectl -n realistic logs -l app=prometheus --tail=40

echo "9. Probar conectividad desde Prometheus a data-service:"
kubectl -n realistic exec $(kubectl get pod -n realistic -l app=prometheus -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://data-service:8080/metrics | head -20
