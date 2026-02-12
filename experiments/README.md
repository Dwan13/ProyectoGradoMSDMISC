# MuBench Experiments

Este directorio contiene escenarios de experimentos reproducibles para medir el rendimiento de microservicios en diferentes configuraciones.

## Escenarios Disponibles

### 1. [Scenario HTTP](scenario-http.md)
**Objetivo:** Medir latencia, throughput y uso de red en comunicación HTTP sin cifrado.

**Casos de uso:**
- Baseline de rendimiento
- Ambiente de desarrollo/staging
- Ambientes donde el cifrado se maneja en capa externa (e.g., Istio service mesh)

**Métricas clave:**
- Latencia inter-servicio
- Throughput (req/s)
- Network bytes TX/RX
- Error rate

---

### 2. [Scenario HTTPS](scenario-https.md)
**Objetivo:** Medir el overhead introducido por TLS en comunicación inter-servicio.

**Casos de uso:**
- Ambientes de producción con seguridad end-to-end
- Compliance requirements (PCI-DSS, HIPAA, etc.)
- Zero-trust networking

**Métricas clave:**
- Overhead de latencia por TLS
- Throughput degradation
- CPU overhead por cifrado/descifrado
- Memory overhead por TLS buffers
- Network overhead por headers TLS

---

## Estructura de un Experimento

Cada escenario sigue esta estructura:

```markdown
1. Objetivo
2. Arquitectura del experimento
3. Requisitos previos
4. Configuración (variables, certificados, etc.)
5. Ejecución paso a paso
6. Métricas a recolectar
7. Análisis de resultados
8. Troubleshooting
9. Referencias
```

## Herramientas Utilizadas

- **k6**: Load testing moderno, scriptable en JavaScript
- **Prometheus**: Métricas de sistema y aplicación
- **Grafana**: Visualización de métricas
- **MicroK8s**: Kubernetes ligero para desarrollo/testing

## Quick Start

### Ejecutar Experimento HTTP

```bash
# 1. Desplegar servicios
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol http

# 2. Ejecutar test
cd Testing
k6 run -e TARGET_URL=http://localhost:31113 -e VUS=20 -e DURATION=60s baseline.js

# 3. Ver métricas en Grafana
# Abrir: http://localhost:3000
```

### Ejecutar Experimento HTTPS

```bash
# 1. Desplegar con TLS
cd ~/muBench
./scripts/deploy_microk8s.sh --start --protocol https

# 2. Ejecutar test
cd Testing
k6 run -e TARGET_URL=http://localhost:31113 -e VUS=20 -e DURATION=60s \
  -e PROTOCOL=https -e INSECURE_SKIP_TLS_VERIFY=true baseline.js

# 3. Analizar overhead
# Comparar con resultados del escenario HTTP
```

## Comparación de Resultados

### Tabla de Benchmarks (Ejemplo)

| Métrica | HTTP | HTTPS | Overhead |
|---------|------|-------|----------|
| Latency P95 | 45ms | 62ms | +37.8% |
| Throughput | 1200 req/s | 980 req/s | -18.3% |
| CPU (avg) | 15% | 28% | +86.7% |
| Memory | 128MB | 145MB | +13.3% |
| Network TX | 2.5 MB/s | 2.8 MB/s | +12.0% |

*Nota: Resultados varían según hardware, workload, y key size*

## Resultados de Experiments

Los resultados de k6 se guardan en:

```
Testing/results/
├── http-baseline-20260211_143022.json
├── http-interservice-20260211_143522.json
├── https-baseline-20260211_144022.json
└── https-interservice-20260211_144522.json
```

### Procesar Resultados JSON

```bash
# Ver resumen
cat results/http-baseline-*.json | jq '.metrics'

# Extraer latencia promedio
cat results/http-baseline-*.json | jq '.metrics.http_req_duration.avg'

# Comparar HTTP vs HTTPS
echo "HTTP:"
cat results/http-*.json | jq '.metrics.http_req_duration.avg'
echo "HTTPS:"
cat results/https-*.json | jq '.metrics.http_req_duration.avg'
```

## Creando Nuevos Experimentos

Template para nuevo escenario:

```markdown
# Experimento: [Nombre del Experimento]

## Objetivo
[Descripción clara del objetivo]

## Arquitectura
[Diagrama o descripción de la topología]

## Configuración
[Variables, prerequisitos, setup]

## Ejecución
[Pasos detallados]

## Métricas
[Qué medir y cómo]

## Análisis
[Cómo interpretar resultados]

## Troubleshooting
[Problemas comunes y soluciones]
```

## Queries Prometheus Útiles

```promql
# Latencia promedio por servicio
rate(http_request_duration_seconds_sum[1m]) / rate(http_request_duration_seconds_count[1m])

# Throughput total
sum(rate(http_requests_total[1m]))

# Error rate
sum(rate(http_requests_total{status_code=~"5.."}[1m])) / sum(rate(http_requests_total[1m]))

# Network I/O
sum(rate(container_network_transmit_bytes_total{namespace="default"}[1m])) by (pod)
sum(rate(container_network_receive_bytes_total{namespace="default"}[1m])) by (pod)

# CPU por pod
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1m])) by (pod)
```

## Dashboards Grafana Recomendados

1. **MuBench Overview**
   - Latencia por servicio
   - Throughput total
   - Error rate
   - Pod health

2. **Inter-Service Communication**
   - Request flow s0→s1→sdb
   - Latency breakdown por hop
   - Network bytes entre servicios

3. **HTTP vs HTTPS Comparison**
   - Side-by-side latency
   - Overhead calculations
   - Resource utilization

4. **Resource Usage**
   - CPU per pod
   - Memory per pod
   - Network I/O

## Best Practices

1. **Ejecutar tests múltiples veces** para obtener medias confiables
2. **Warm-up period** antes de medir (primeros 30s no cuentan)
3. **Baseline estable** antes de experimentos
4. **Documentar configuración** de hardware y Kubernetes
5. **Versionar resultados** con timestamps y git commits

## Contribuir Nuevos Experimentos

Para agregar un nuevo escenario:

1. Crear archivo `scenario-[nombre].md`
2. Seguir template de estructura
3. Incluir scripts k6 si es necesario
4. Actualizar este README
5. Documentar métricas esperadas

## Referencias

- [k6 Documentation](https://k6.io/docs/)
- [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Guide](https://grafana.com/docs/grafana/latest/dashboards/)
- [MuBench Manual](../Docs/Manual.md)
