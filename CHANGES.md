# MuBench - Actualizaciones de Comunicación Inter-Servicio

## 🎯 Cambios Implementados

Este documento describe las actualizaciones realizadas al proyecto MuBench para implementar comunicación real HTTP/HTTPS entre microservicios con métricas completas.

## 📋 Resumen de Cambios

### ✅ Completado

1. **Comunicación Inter-Servicio Real**
   - Service0 → Service1 → ServiceDB (cadena de llamadas HTTP/HTTPS)
   - Endpoints REST implementados: `/process`, `/validate`, `/query`

2. **Métricas Prometheus Mejoradas**
   - `http_request_duration_seconds` - Histograma de latencia
   - `http_requests_total` - Contador de requests
   - Métricas existentes de muBench preservadas

3. **Soporte HTTP/HTTPS**
   - Variable de entorno `COMM_PROTOCOL` (http|https)
   - Certificados TLS auto-firmados para modo HTTPS
   - Sin service mesh (Istio no requerido)

4. **Manifests Kubernetes Actualizados**
   - Services con ClusterIP (en vez de NodePort)
   - Readiness y Liveness probes
   - Annotations de Prometheus para auto-discovery
   - Soporte para volumenes TLS

5. **k6 Reemplaza JMeter**
   - Scripts JavaScript parametrizables
   - Salida en JSON para análisis
   - Tests de baseline y inter-service communication

6. **Carpeta de Experiments**
   - `/experiments/scenario-http.md` - Guía para HTTP
   - `/experiments/scenario-https.md` - Guía para HTTPS con TLS overhead
   - Instrucciones reproducibles paso a paso

7. **Script Bash Actualizado**
   - Opción `--protocol http|https`
   - Generación automática de certificados TLS
   - Integración con k6
   - Preserva flujo de despliegue existente

## 📁 Archivos Modificados/Creados

### Nuevos Archivos

```
ServiceCell/CellController-enhanced.py       # Enhanced version con endpoints HTTP/HTTPS
Testing/baseline.js                          # k6 baseline test
Testing/inter-service-test.js                # k6 inter-service test
experiments/README.md                        # Guía de experimentos
experiments/scenario-http.md                 # Escenario HTTP
experiments/scenario-https.md                # Escenario HTTPS
CHANGES.md                                   # Este archivo
```

### Archivos Modificados

```
scripts/deploy_microk8s.sh                   # Soporta HTTP/HTTPS, k6, TLS
Deployers/K8sDeployer/Templates/DeploymentTemplate.yaml  # Probes, env vars
Deployers/K8sDeployer/Templates/ServiceTemplate.yaml     # ClusterIP, annotations
```

## 🚀 Uso Rápido

### Despliegue con HTTP (sin cifrado)

```bash
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol http
```

### Despliegue con HTTPS (con TLS)

```bash
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol https
```

### Ejecutar Tests Manualmente

```bash
cd ~/muBench/Testing

# Test baseline
k6 run -e TARGET_URL=http://localhost:31113/s0 \
       -e VUS=20 -e DURATION=60s baseline.js

# Test inter-service
k6 run -e TARGET_URL=http://localhost:31113 \
       -e VUS=20 -e DURATION=60s inter-service-test.js
```

## 📊 Métricas Disponibles

### Nuevas Métricas (Prometheus)

```promql
# Latencia de requests HTTP
http_request_duration_seconds{service="s0",endpoint="/process"}

# Total de requests
http_requests_total{service="s0",endpoint="/process",status_code="200"}

# Network bytes (ya existente en K8s)
container_network_transmit_bytes_total{namespace="default",pod=~"s0.*"}
container_network_receive_bytes_total{namespace="default",pod=~"s0.*"}
```

### Métricas Existentes (Preservadas)

```promql
# MuBench internal processing
mub_internal_processing_latency_milliseconds

# MuBench external processing
mub_external_processing_latency_milliseconds

# MuBench request processing
mub_request_processing_latency_milliseconds
```

## 🔍 Endpoints de Servicio

| Servicio | Endpoint | Descripción | Llamada Externa |
|----------|----------|-------------|-----------------|
| s0 | `/process` | Procesa request, llama a s1 | → s1:/validate |
| s1 | `/validate` | Valida datos, llama a sdb | → sdb1:/query |
| sdb1 | `/query` | Query a "base de datos" | (ninguna) |
| Todos | `/metrics` | Métricas Prometheus | - |
| Todos | `/health` | Health check | - |
| Todos | `/ready` | Readiness check | - |

## 🔐 Modo HTTPS - Detalles TLS

### Certificados Auto-Firmados

Los certificados se generan automáticamente en `~/muBench/tls-certs/`:

```bash
s0-cert.pem, s0-key.pem
s1-cert.pem, s1-key.pem
sdb1-cert.pem, sdb1-key.pem
```

### Secrets de Kubernetes

```bash
microk8s kubectl get secrets -n default | grep tls
s0-tls-secret    kubernetes.io/tls   2      1m
s1-tls-secret    kubernetes.io/tls   2      1m
sdb1-tls-secret  kubernetes.io/tls   2      1m
```

### Variables de Entorno

```bash
COMM_PROTOCOL=https  # o http
```

## 📈 Experimentos Reproducibles

Ver documentación completa en:

- [experiments/README.md](experiments/README.md) - Guía general
- [experiments/scenario-http.md](experiments/scenario-http.md) - HTTP sin cifrado
- [experiments/scenario-https.md](experiments/scenario-https.md) - HTTPS con TLS

### Objetivos de los Experimentos

1. **Latencia inter-servicio**: Medir tiempo de comunicación s0→s1→sdb
2. **Throughput interno**: Requests/sec entre servicios
3. **Network bytes**: Bytes transmitidos/recibidos por pod
4. **Overhead TLS**: Comparar HTTP vs HTTPS

## 🛠️ Troubleshooting

### Los pods no arrancan

```bash
microk8s kubectl get pods -n default
microk8s kubectl describe pod <pod-name>
microk8s kubectl logs <pod-name>
```

### k6 no instalado

El script intentará instalar k6 automáticamente en Linux. Para instalación manual:

```bash
# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# macOS
brew install k6
```

### Métricas no aparecen en Prometheus

Verificar que los pods tengan las annotations correctas:

```bash
microk8s kubectl get pod <pod-name> -o yaml | grep -A3 annotations
```

Debe incluir:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
```

### Error de certificados TLS

En modo HTTPS, verificar que los secrets existan:

```bash
microk8s kubectl get secrets -n default | grep tls
```

Regenerar certificados:

```bash
rm -rf ~/muBench/tls-certs
./scripts/deploy_microk8s.sh --start --protocol https
```

## 🎓 Arquitectura sin Cambios Mayores

### ✅ Preservado

- Flujo principal de muBench
- Generación de service graphs
- Workload models
- Sistema de métricas existente
- Compatibilidad con gRPC
- Configuración de Prometheus/Grafana

### ✨ Añadido

- Endpoints REST específicos para inter-service calls
- Métricas estándar Prometheus (complementan existentes)
- Variable COMM_PROTOCOL para HTTP/HTTPS
- Probes de K8s (readiness/liveness)
- k6 para load testing moderno

## 📚 Referencias

- [k6 Documentation](https://k6.io/docs/)
- [Prometheus Client Python](https://github.com/prometheus/client_python)
- [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [TLS Certificates](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## 🤝 Contribuir

Para extender estos cambios:

1. Nuevos endpoints: Modificar `ServiceCell/CellController-enhanced.py`
2. Nuevas métricas: Usar `prometheus_client` en Python
3. Nuevos tests: Crear scripts k6 en `Testing/`
4. Nuevos experimentos: Documentar en `experiments/`

## ⚙️ Next Steps (Opcional)

Mejoras futuras que podrían implementarse:

- [ ] Integración con Jaeger para distributed tracing
- [ ] Soporte para mTLS (mutual TLS)
- [ ] Dashboard Grafana pre-configurado
- [ ] CI/CD pipeline para tests automáticos
- [ ] Exportador de métricas TLS-específicas
- [ ] Comparación automática HTTP vs HTTPS
