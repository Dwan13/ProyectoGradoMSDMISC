# Experimento: Comunicación HTTP entre Microservicios

## Objetivo
Medir latencia, throughput y uso de red en comunicación HTTP sin cifrado entre microservicios en MuBench.

## Arquitectura del Experimento

```
Cliente (k6) → Gateway Nginx → Service0 (s0) → Service1 (s1) → ServiceDB (sdb1)
                                  ↓ /process      ↓ /validate     ↓ /query
```

## Requisitos Previos

1. MicroK8s instalado y corriendo
2. kube-prom-stack desplegado (Prometheus + Grafana)
3. k6 instalado localmente
4. Servicios de muBench desplegados

## Configuración

### 1. Variables de Entorno

```bash
export COMM_PROTOCOL=http
export NAMESPACE=default
export VUS=20
export DURATION=120s
```

### 2. Desplegar Servicios en Modo HTTP

```bash
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol http
```

## Ejecución del Experimento

### Paso 1: Verificar Estado de los Servicios

```bash
microk8s kubectl get pods -n default
microk8s kubectl get svc -n default
```

Esperar hasta que todos los pods estén en estado `Running` y `2/2 Ready`.

### Paso 2: Ejecutar Prueba de Carga con k6

#### Test Básico (endpoint principal)

```bash
cd ~/muBench/Testing

k6 run --out json=results/http-baseline-$(date +%Y%m%d_%H%M%S).json \
  -e TARGET_URL=http://localhost:31113/s0 \
  -e VUS=20 \
  -e DURATION=120s \
  -e PROTOCOL=http \
  baseline.js
```

#### Test de Comunicación Inter-Servicio

```bash
k6 run --out json=results/http-interservice-$(date +%Y%m%d_%H%M%S).json \
  -e TARGET_URL=http://localhost:31113 \
  -e VUS=20 \
  -e DURATION=120s \
  -e PROTOCOL=http \
  inter-service-test.js
```

### Paso 3: Monitorizar Métricas en Prometheus

Abrir Prometheus en `http://localhost:9090` y ejecutar las siguientes queries:

#### Latencia por Servicio

```promql
# Latencia P95 por servicio
histogram_quantile(0.95, 
  rate(http_request_duration_seconds_bucket[1m])
)

# Latencia promedio
rate(http_request_duration_seconds_sum[1m]) / 
rate(http_request_duration_seconds_count[1m])
```

#### Throughput (Requests/sec)

```promql
# Total de requests por segundo
sum(rate(http_requests_total[1m])) by (service)

# Requests por endpoint
sum(rate(http_requests_total[1m])) by (service, endpoint)
```

#### Network Bytes

```promql
# Bytes enviados por servicio
sum(rate(container_network_transmit_bytes_total{namespace="default"}[1m])) by (pod)

# Bytes recibidos por servicio
sum(rate(container_network_receive_bytes_total{namespace="default"}[1m])) by (pod)
```

#### Request Rate por Service

```promql
# External processing latency
mub_external_processing_latency_milliseconds

# Internal processing latency
mub_internal_processing_latency_milliseconds

# Total request processing
mub_request_processing_latency_milliseconds
```

### Paso 4: Visualizar en Grafana

Acceder a Grafana en `http://localhost:3000` (usuario: `admin`, ver credenciales en `~/.mubench_credentials`)

#### Dashboard Recomendado

Crear un dashboard con los siguientes paneles:

1. **Latencia Inter-Servicio** (Graph)
   - Query: `rate(http_request_duration_seconds_sum[1m]) / rate(http_request_duration_seconds_count[1m])`
   - Group by: `service`

2. **Throughput por Endpoint** (Graph)
   - Query: `sum(rate(http_requests_total[1m])) by (endpoint)`

3. **Network I/O** (Graph)
   - Query TX: `sum(rate(container_network_transmit_bytes_total{namespace="default"}[1m])) by (pod)`
   - Query RX: `sum(rate(container_network_receive_bytes_total{namespace="default"}[1m])) by (pod)`

4. **Error Rate** (Stat)
   - Query: `sum(rate(http_requests_total{status_code=~"5.."}[1m])) / sum(rate(http_requests_total[1m]))`

5. **Response Time P95/P99** (Graph)
   - P95: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))`
   - P99: `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))`

## Resultados Esperados

### Métricas Clave a Recolectar

| Métrica | Objetivo | Unidad |
|---------|----------|--------|
| Latencia P95 (s0) | < 100ms | ms |
| Latencia P95 (s1) | < 100ms | ms |
| Latencia P95 (sdb1) | < 100ms | ms |
| Throughput Total | > 500 req/s | req/s |
| Error Rate | < 1% | % |
| Network TX (por pod) | Variable | bytes/s |
| Network RX (por pod) | Variable | bytes/s |

### Análisis de k6 JSON Output

Procesar resultados con:

```bash
# Ver resumen de métricas
cat results/http-baseline-*.json | jq '.metrics'

# Extraer latencias
cat results/http-baseline-*.json | jq '.metrics.http_req_duration'

# Contar errores
cat results/http-baseline-*.json | jq '.metrics.http_req_failed'
```

## Cleanup

```bash
# Detener port-forwards
./scripts/deploy_microk8s.sh --stop

# (Opcional) Eliminar deployments
microk8s kubectl delete deployment --all -n default
```

## Troubleshooting

### Los pods no arrancan

```bash
microk8s kubectl describe pod <pod-name> -n default
microk8s kubectl logs <pod-name> -n default
```

### k6 no puede conectar

```bash
# Verificar que el gateway nginx esté corriendo
microk8s kubectl get svc gw-nginx -n default

# Verificar el NodePort
microk8s kubectl get svc gw-nginx -o jsonpath='{.spec.ports[0].nodePort}'

# Probar manualmente
curl http://localhost:31113/s0
```

### Métricas no aparecen en Prometheus

```bash
# Verificar que Prometheus esté scrapeando los pods
curl http://localhost:9090/api/v1/targets

# Verificar métricas en el pod directamente
microk8s kubectl port-forward pod/<s0-pod-name> 8080:8080
curl http://localhost:8080/metrics
```

## Referencias

- [k6 Documentation](https://k6.io/docs/)
- [Prometheus Query Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)
