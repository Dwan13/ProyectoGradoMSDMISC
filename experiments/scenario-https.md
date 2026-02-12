# Experimento: Comunicación HTTPS entre Microservicios con TLS

## Objetivo
Medir latencia, throughput, uso de red y **overhead de TLS** en comunicación HTTPS cifrada entre microservicios en MuBench.

## Arquitectura del Experimento

```
Cliente (k6) → Gateway Nginx → Service0 (s0) ──[HTTPS]──> Service1 (s1) ──[HTTPS]──> ServiceDB (sdb1)
               [HTTP]            ↓ /process                  ↓ /validate                ↓ /query
                                [TLS handshake]           [TLS handshake]          [TLS handshake]
```

## Requisitos Previos

1. MicroK8s instalado y corriendo
2. kube-prom-stack desplegado
3. k6 instalado localmente
4. Certificados TLS auto-firmados generados

## Configuración

### 1. Variables de Entorno

```bash
export COMM_PROTOCOL=https
export NAMESPACE=default
export VUS=20
export DURATION=120s
export INSECURE_SKIP_TLS_VERIFY=true  # Para certificados auto-firmados
```

### 2. Generar Certificados TLS Auto-Firmados

El script de despliegue automáticamente generará certificados, pero puedes crearlos manualmente:

```bash
cd ~/muBench

# Crear directorio para certificados
mkdir -p tls-certs

# Generar certificados para cada servicio
for SERVICE in s0 s1 sdb1; do
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout tls-certs/${SERVICE}-key.pem \
    -out tls-certs/${SERVICE}-cert.pem \
    -days 365 \
    -subj "/CN=${SERVICE}.default.svc.cluster.local/O=muBench/C=US"
done
```

### 3. Crear Secrets de Kubernetes

```bash
for SERVICE in s0 s1 sdb1; do
  microk8s kubectl create secret tls ${SERVICE}-tls-secret \
    --cert=tls-certs/${SERVICE}-cert.pem \
    --key=tls-certs/${SERVICE}-key.pem \
    -n default \
    --dry-run=client -o yaml | microk8s kubectl apply -f -
done
```

### 4. Desplegar Servicios en Modo HTTPS

```bash
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol https
```

## Ejecución del Experimento

### Paso 1: Verificar Configuración TLS

```bash
# Verificar que los secrets existan
microk8s kubectl get secrets -n default | grep tls

# Verificar que los pods tengan montados los certificados
microk8s kubectl describe pod -l app=s0 -n default | grep -A5 "Mounts"

# Verificar variable de entorno COMM_PROTOCOL
microk8s kubectl exec -it deployment/s0 -- env | grep COMM_PROTOCOL
```

### Paso 2: Test Manual de HTTPS

```bash
# Port-forward para probar directamente
microk8s kubectl port-forward svc/s0 8443:443 &

# Test con curl (ignorando certificado auto-firmado)
curl -k https://localhost:8443/process
curl -k https://localhost:8443/health

# Ver métricas
curl -k https://localhost:8443/metrics
```

### Paso 3: Ejecutar Prueba de Carga con k6

#### Test Básico HTTPS

```bash
cd ~/muBench/Testing

k6 run --out json=results/https-baseline-$(date +%Y%m%d_%H%M%S).json \
  -e TARGET_URL=http://localhost:31113/s0 \
  -e VUS=20 \
  -e DURATION=120s \
  -e PROTOCOL=https \
  -e INSECURE_SKIP_TLS_VERIFY=true \
  baseline.js
```

#### Test de Comunicación Inter-Servicio HTTPS

```bash
k6 run --out json=results/https-interservice-$(date +%Y%m%d_%H%M%S).json \
  -e TARGET_URL=http://localhost:31113 \
  -e VUS=20 \
  -e DURATION=120s \
  -e PROTOCOL=https \
  -e INSECURE_SKIP_TLS_VERIFY=true \
  inter-service-test.js
```

### Paso 4: Comparar con Escenario HTTP

Para medir el **overhead de TLS**, ejecutar el mismo test en modo HTTP y comparar:

```bash
# Redeployar en modo HTTP
./scripts/deploy_microk8s.sh --start --protocol http

# Ejecutar el mismo test
k6 run --out json=results/http-comparison-$(date +%Y%m%d_%H%M%S).json \
  -e TARGET_URL=http://localhost:31113 \
  -e VUS=20 \
  -e DURATION=120s \
  -e PROTOCOL=http \
  inter-service-test.js
```

## Métricas Clave para Medir Overhead TLS

### En Prometheus

```promql
# Diferencia de latencia HTTP vs HTTPS
# (ejecutar en ventanas temporales separadas)
avg(rate(http_request_duration_seconds_sum[1m])) by (service)

# Network bytes - TLS añade overhead de cifrado
sum(rate(container_network_transmit_bytes_total{namespace="default"}[1m])) by (pod)
```

### Calcular TLS Overhead

| Métrica | HTTP | HTTPS | Overhead | % Increase |
|---------|------|-------|----------|------------|
| Latencia P95 (ms) | ______ | ______ | ______ | ____% |
| Throughput (req/s) | ______ | ______ | ______ | ____% |
| Network TX (KB/s) | ______ | ______ | ______ | ____% |
| CPU Usage (%) | ______ | ______ | ______ | ____% |
| Memory (MB) | ______ | ______ | ______ | ____% |

**Overhead esperado de TLS:**
- Latencia: +10-30% (dependiendo de CPU y key size)
- Throughput: -10-20% (por handshake overhead)
- Network: +5-10% (por headers TLS y padding)
- CPU: +20-40% (por operaciones criptográficas)

## Queries Avanzadas en Prometheus

### TLS Handshake Time

```promql
# Tiempo de handshake TLS (si métrica disponible)
rate(http_request_tls_handshake_duration_seconds_sum[1m]) / 
rate(http_request_tls_handshake_duration_seconds_count[1m])
```

### CPU por Proceso (TLS intensivo)

```promql
# CPU por pod
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1m])) by (pod)
```

### Memory por TLS Buffers

```promql
# Memoria por pod
sum(container_memory_working_set_bytes{namespace="default"}) by (pod)
```

## Visualización en Grafana

### Dashboard: HTTP vs HTTPS Comparison

Crear paneles lado a lado:

1. **Latency Comparison** (Graph)
   - Query A (HTTP): `avg(rate(http_request_duration_seconds_sum{protocol="http"}[1m]))`
   - Query B (HTTPS): `avg(rate(http_request_duration_seconds_sum{protocol="https"}[1m]))`

2. **Throughput Comparison** (Graph)
   - Query A: `sum(rate(http_requests_total{protocol="http"}[1m]))`
   - Query B: `sum(rate(http_requests_total{protocol="https"}[1m]))`

3. **Network Overhead** (Graph)
   - TX bytes comparison por pod

4. **CPU Impact** (Graph)
   - CPU usage por pod durante HTTP vs HTTPS

5. **TLS Overhead Percentage** (Stat)
   - Formula: `((https_latency - http_latency) / http_latency) * 100`

## Análisis de Resultados

### Script de Comparación Python

```python
#!/usr/bin/env python3
import json
import sys

def compare_results(http_file, https_file):
    with open(http_file) as f:
        http_data = json.load(f)
    with open(https_file) as f:
        https_data = json.load(f)
    
    http_latency = http_data['metrics']['http_req_duration']['avg']
    https_latency = https_data['metrics']['http_req_duration']['avg']
    
    overhead_ms = https_latency - http_latency
    overhead_pct = (overhead_ms / http_latency) * 100
    
    print(f"HTTP Average Latency:  {http_latency:.2f} ms")
    print(f"HTTPS Average Latency: {https_latency:.2f} ms")
    print(f"TLS Overhead:          {overhead_ms:.2f} ms ({overhead_pct:.1f}%)")

if __name__ == '__main__':
    compare_results(sys.argv[1], sys.argv[2])
```

Ejecutar:

```bash
python3 compare_tls_overhead.py \
  results/http-comparison-*.json \
  results/https-interservice-*.json
```

## Troubleshooting

### Error: Certificate Validation Failed

```bash
# Asegurarse de usar -k con curl
curl -k https://...

# En k6, verificar INSECURE_SKIP_TLS_VERIFY=true
```

### Error: Pod no puede conectar a otro servicio vía HTTPS

```bash
# Debug desde dentro del pod
microk8s kubectl exec -it deployment/s0 -- sh

# Instalar curl si no existe
apk add curl

# Test manual
curl -k https://s1.default.svc.cluster.local/validate
```

### TLS Handshake Timeout

```bash
# Verificar que el puerto 443 esté expuesto
microk8s kubectl get svc s1 -o yaml | grep -A5 ports

# Verificar que el certificado sea válido
openssl s_client -connect s1.default.svc.cluster.local:443 -showcerts
```

### Overhead muy alto (>50%)

Posibles causas:
- Certificados con keys muy grandes (usar RSA 2048 en vez de 4096)
- CPU limitada en los pods
- Session reuse deshabilitado
- TLS 1.0/1.1 en vez de 1.3 (verificar versión)

## Optimizaciones de TLS

Para reducir overhead:

1. **Habilitar TLS Session Reuse**
   - Configurar en nginx/ingress
   
2. **Usar TLS 1.3**
   - Handshake más rápido (1-RTT vs 2-RTT)

3. **Certificate Pinning**
   - Evitar validación completa en cada request

4. **HTTP/2 con TLS**
   - Multiplexing reduce handshakes

## Referencias

- [TLS Performance Tuning](https://istlsfastyet.com/)
- [k6 HTTPS Testing](https://k6.io/docs/using-k6/protocols/ssl-tls/)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
